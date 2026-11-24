from pathlib import Path

import httpx
from azure_functions_agents.discovery.mcp import discover_mcp_servers


def configure_mcp_transport(app_root: Path) -> None:
    discovered = discover_mcp_servers(app_root)
    if discovered.failed_loads:
        names = ", ".join(name for name, _ in discovered.failed_loads)
        raise RuntimeError(f"Required MCP servers could not be loaded: {names}")
    for name, server in discovered.servers.items():
        # The pinned runtime does not expose its authenticated HTTP client in mcp.json.
        client = getattr(server, "_httpx_client", None)
        if not isinstance(client, httpx.AsyncClient):
            raise RuntimeError(f"MCP HTTP client for {name} changed; revalidate the transport compatibility fix.")
        client.timeout = httpx.Timeout(30, read=120)
        server.request_timeout = 150
