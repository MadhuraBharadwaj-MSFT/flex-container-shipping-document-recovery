import base64
import binascii
import hashlib
import json
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path

import azure.functions as func
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.identity.aio import DefaultAzureCredential
from azure.servicebus import ServiceBusMessage
from azure.servicebus.aio import ServiceBusClient
from azure.storage.blob import ContentSettings
from azure.storage.blob.aio import BlobServiceClient
from azurefunctions.extensions.http.fastapi import JSONResponse, Request, Response
from jsonschema import Draft202012Validator

from message_tracking import summarize

bp = func.Blueprint()
schema = Draft202012Validator(
    json.loads(Path(__file__).with_name("shipment-schema.json").read_text())
)
RUN_ID = re.compile(r"^[a-f0-9]{32}$")
RUN_LIFETIME = timedelta(minutes=20)
MAX_REQUEST_BYTES = 16 * 1024


@lru_cache
def storage() -> BlobServiceClient:
    return BlobServiceClient(
        os.environ["DATA_STORAGE_BLOB_URL"],
        credential=DefaultAzureCredential(),
    )


def json_response(data: dict, status: int = 200) -> JSONResponse:
    return JSONResponse(
        data,
        status_code=status,
        headers={"Cache-Control": "no-store"},
    )


def authorized(req: Request) -> bool:
    encoded = req.headers.get("x-ms-client-principal", "")
    try:
        principal = json.loads(base64.b64decode(encoded, validate=True))
    except (ValueError, binascii.Error, UnicodeDecodeError):
        return False
    owner_id = os.environ.get("DEMO_OWNER_ID", "")
    return (
        isinstance(principal, dict)
        and bool(owner_id)
        and principal.get("identityProvider") == "aad"
        and principal.get("userId") == owner_id
    )


def manifest_blob(run_id: str):
    return storage().get_blob_client("demo-runs", f"{run_id}.json")


async def read_json_blob(container: str, name: str) -> dict:
    blob = storage().get_blob_client(container, name)
    return json.loads(await (await blob.download_blob()).readall())


async def read_text_blob(container: str, name: str) -> str:
    blob = storage().get_blob_client(container, name)
    return (await (await blob.download_blob()).readall()).decode("utf-8")


def prepare_submission(payload: dict) -> tuple[dict, dict]:
    run_id = payload.get("request_id", "")
    if not isinstance(run_id, str) or not RUN_ID.fullmatch(run_id):
        raise ValueError(
            "request_id must contain 32 lowercase hexadecimal characters."
        )
    shipment = payload.get("shipment")
    if not isinstance(shipment, dict):
        raise ValueError("shipment must be a JSON object.")

    id_fields = [
        key for key in ("shipment_id", "shipmentId")
        if key in shipment
    ]
    if len(id_fields) != 1:
        raise ValueError(
            "Include exactly one shipment_id or shipmentId field."
        )
    shipment = dict(shipment)
    shipment[id_fields[0]] = run_id

    run = {
        "id": run_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "input": shipment,
        "repair_expected": not schema.is_valid(shipment),
        "sent": False,
        "request_hash": hashlib.sha256(
            json.dumps(payload, sort_keys=True, allow_nan=False).encode()
        ).hexdigest(),
    }
    return run, shipment


async def send_shipment(run: dict, shipment: dict) -> None:
    namespace = os.environ[
        "ServiceBusConnection__fullyQualifiedNamespace"
    ]
    queue_name = os.environ["SHIPMENT_QUEUE"]
    async with (
        DefaultAzureCredential() as credential,
        ServiceBusClient(
            namespace,
            credential,
            uamqp_transport=True,
        ) as client,
        client.get_queue_sender(queue_name) as sender,
    ):
        await sender.send_messages(
            ServiceBusMessage(
                json.dumps(shipment, allow_nan=False),
                message_id=run["id"],
                correlation_id=run["id"],
                content_type="application/json",
            )
        )


async def read_events(run_id: str) -> list[dict]:
    events = []
    container = storage().get_container_client("demo-runs")
    async for blob in container.list_blobs(
        name_starts_with=f"flow/{run_id}/"
    ):
        if len(events) == 50:
            break
        events.append(
            json.loads(
                await (
                    await container.download_blob(blob.name)
                ).readall()
            )
        )
    return events


async def status(run: dict) -> dict:
    result = None
    html = None
    try:
        result = await read_json_blob(
            "generated-documents",
            f"{run['id']}/result.json",
        )
        html = await read_text_blob(
            "generated-documents",
            result["html_blob"],
        )
    except ResourceNotFoundError:
        pass

    flow = summarize(await read_events(run["id"]))
    complete = result is not None
    created = datetime.fromisoformat(run["created_at"])
    return {
        "id": run["id"],
        "created_at": run["created_at"],
        "expired": datetime.now(timezone.utc) - created > RUN_LIFETIME,
        "complete": complete,
        "repair_expected": run["repair_expected"],
        "input": run["input"],
        "canonical": result["shipment"] if result else None,
        "recovered_by_hosted_skill": (
            result["recovered_by_hosted_skill"] if result else False
        ),
        "pdf_bytes": result["pdf_bytes"] if result else None,
        "pdf_url": (
            f"/api/demo/runs/{run['id']}/pdf" if result else None
        ),
        "html": html,
        "flow": flow,
    }


@bp.route(
    route="demo/runs",
    methods=["POST"],
    auth_level=func.AuthLevel.ANONYMOUS,
)
async def submit_demo(req: Request) -> JSONResponse:
    if not authorized(req):
        return json_response(
            {"error": "Sign in with the configured Microsoft demo-owner account."},
            403,
        )
    if req.headers.get("content-type", "").split(";")[0].strip() != "application/json":
        return json_response({"error": "Use application/json."}, 415)
    body = await req.body()
    if len(body) > MAX_REQUEST_BYTES:
        return json_response({"error": "The request is too large."}, 413)

    try:
        payload = json.loads(body)
        if not isinstance(payload, dict):
            raise ValueError("The request must be a JSON object.")
        run, shipment = prepare_submission(payload)
    except (ValueError, TypeError) as exc:
        return json_response({"error": str(exc)}, 400)

    blob = manifest_blob(run["id"])
    try:
        await blob.upload_blob(
            json.dumps(run, allow_nan=False),
            overwrite=False,
            content_settings=ContentSettings(
                content_type="application/json"
            ),
        )
    except ResourceExistsError:
        existing = await read_json_blob("demo-runs", f"{run['id']}.json")
        if existing["request_hash"] != run["request_hash"]:
            return json_response(
                {"error": "This request ID was already used for different input."},
                409,
            )
        run = existing
        shipment = run["input"]
        if run.get("sent"):
            return json_response({"id": run["id"]}, 202)

    try:
        await send_shipment(run, shipment)
        run["sent"] = True
        await blob.upload_blob(
            json.dumps(run, allow_nan=False),
            overwrite=True,
            content_settings=ContentSettings(
                content_type="application/json"
            ),
        )
    except Exception:
        logging.exception("shipment_submission_failed run_id=%s", run["id"])
        return json_response(
            {
                "error": "The shipment could not be sent to Service Bus.",
                "id": run["id"],
            },
            503,
        )
    return json_response({"id": run["id"]}, 202)


@bp.route(
    route="demo/runs/{run_id}",
    methods=["GET"],
    auth_level=func.AuthLevel.ANONYMOUS,
)
async def demo_status(req: Request) -> JSONResponse:
    if not authorized(req):
        return json_response(
            {"error": "Sign in with the configured Microsoft demo-owner account."},
            403,
        )
    run_id = req.path_params.get("run_id", "")
    if not RUN_ID.fullmatch(run_id):
        return json_response({"error": "Invalid run ID."}, 400)
    try:
        run = await read_json_blob("demo-runs", f"{run_id}.json")
    except ResourceNotFoundError:
        return json_response({"error": "Run not found."}, 404)
    return json_response(await status(run))


@bp.route(
    route="demo/runs/{run_id}/pdf",
    methods=["GET"],
    auth_level=func.AuthLevel.ANONYMOUS,
)
async def demo_pdf(req: Request) -> Response:
    if not authorized(req):
        return Response(
            content=b"Access denied.",
            status_code=403,
            media_type="text/plain",
        )
    run_id = req.path_params.get("run_id", "")
    if not RUN_ID.fullmatch(run_id):
        return Response(
            content=b"Invalid run ID.",
            status_code=400,
            media_type="text/plain",
        )
    try:
        result = await read_json_blob(
            "generated-documents",
            f"{run_id}/result.json",
        )
        pdf = await (
            await storage()
            .get_blob_client(
                "generated-documents",
                result["pdf_blob"],
            )
            .download_blob()
        ).readall()
    except ResourceNotFoundError:
        return Response(
            content=b"PDF not found.",
            status_code=404,
            media_type="text/plain",
        )
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={
            "Cache-Control": "no-store",
            "Content-Disposition": (
                f'inline; filename="{run_id}-packing-slip.pdf"'
            ),
        },
    )


@bp.route(
    route="demo/access",
    methods=["GET"],
    auth_level=func.AuthLevel.ANONYMOUS,
)
async def demo_access(req: Request) -> JSONResponse:
    if not authorized(req):
        return json_response(
            {"error": "Sign in with the configured Microsoft demo-owner account."},
            403,
        )
    return json_response({"allowed": True})
