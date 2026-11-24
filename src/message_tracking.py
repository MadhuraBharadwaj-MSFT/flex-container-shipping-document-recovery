STAGES = {
    "submitted": "Submitted to Service Bus",
    "received": "Document worker received the shipment",
    "rejected": "Validation failed; Service Bus is moving it to the DLQ",
    "requeued": "Hosted Skill repaired and requeued the shipment",
    "requeue_rejected": "The repaired shipment failed deterministic validation",
    "output_saved": "Canonical HTML and PDF saved to Blob Storage",
}

ORDER = {
    name: index for index, name in enumerate(STAGES)
}


def summarize(events: list[dict]) -> dict:
    ordered = sorted(
        events,
        key=lambda item: (
            item.get("observed_at", ""),
            ORDER.get(item.get("stage", ""), -1),
        ),
    )
    latest = max(
        ordered,
        key=lambda item: ORDER.get(item.get("stage", ""), -1),
        default={"stage": "submitted"},
    )
    return {
        "latest": latest.get("stage", "submitted"),
        "label": STAGES.get(
            latest.get("stage", ""),
            "Waiting for a confirmed stage",
        ),
        "events": ordered,
    }
