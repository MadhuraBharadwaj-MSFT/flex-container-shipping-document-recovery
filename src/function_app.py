from pathlib import Path

from azure_functions_agents import create_function_app

from demo_api import bp as demo_blueprint
from mcp_transport import configure_mcp_transport

configure_mcp_transport(Path(__file__).parent)
app = create_function_app(app_root=Path(__file__).parent)
app.register_functions(demo_blueprint)
