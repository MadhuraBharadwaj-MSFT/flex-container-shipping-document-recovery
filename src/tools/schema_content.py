import json
from pathlib import Path
from typing import Any

from azure_functions_agents import tool


@tool
def load_repair_contract() -> dict[str, Any]:
    """Load the validated local mirror of the Blob repair contract."""
    value = json.loads(
        Path(__file__).resolve().parents[1]
        .joinpath("repair-contract.json")
        .read_text(encoding="utf-8")
    )
    if not isinstance(value, dict):
        raise ValueError("Repair contract must be a JSON object.")
    return value
