import base64
import json
from typing import Annotated, Any

from azure_functions_agents import tool
from jsonschema import Draft202012Validator


@tool
def decode_schema_content(
    content: Annotated[str, "The exact base64 string from the schema connector's $content field."],
) -> dict[str, Any]:
    """Decode the Blob connector's base64 schema content into a validated JSON schema."""
    if not content or len(content) > 16384:
        raise ValueError("Schema content must contain between 1 and 16384 base64 characters.")
    schema = json.loads(base64.b64decode(content, validate=True).decode("utf-8"))
    if not isinstance(schema, dict):
        raise ValueError("Decoded schema content must be a JSON object.")
    Draft202012Validator.check_schema(schema)
    return schema
