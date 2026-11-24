import argparse
import os
import time
from pathlib import Path

from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload the shipping schema for the hosted skill to read through MCP.")
    parser.add_argument("--storage-account", default=os.environ.get("AZURE_STORAGE_ACCOUNT_NAME"))
    args = parser.parse_args()
    if not args.storage_account:
        parser.error("Set AZURE_STORAGE_ACCOUNT_NAME or pass --storage-account")
    schema = Path(__file__).resolve().parents[1] / "src" / "shipment-schema.json"
    with DefaultAzureCredential() as credential:
        with BlobServiceClient(
            f"https://{args.storage_account}.blob.core.windows.net", credential,
        ) as client:
            blob = client.get_blob_client("schemas", "shipment-schema.json")
            for attempt in range(12):
                try:
                    blob.upload_blob(
                        schema.read_bytes(), overwrite=True,
                        content_settings=ContentSettings(content_type="application/json"),
                    )
                    break
                except HttpResponseError as exc:
                    if exc.status_code != 403 or attempt == 11:
                        raise
                    print("Waiting 10 seconds for Blob role assignments to propagate...", flush=True)
                    time.sleep(10)
    print("Uploaded schemas/shipment-schema.json")


if __name__ == "__main__":
    main()
