"""Application configuration loaded from environment variables.

Uses pure ``os.environ`` (no pydantic-settings dependency) to keep the
backend's dependency surface small. Fails fast on startup if required
configuration is missing, unless ``DEV_MODE=true`` is set, in which case
the application starts with placeholder values and logs a warning. This
lets developers boot the FastAPI app for smoke testing (e.g., ``/api/health``
and SSE-format checks) without a real Foundry deployment.

Environment variables
---------------------
FOUNDRY_PROJECT_ENDPOINT : str
    Required. Foundry V2 project endpoint URL, e.g.
    ``https://<aiservices-name>.services.ai.azure.com/api/projects/<project-name>``.
FOUNDRY_AGENT_NAME : str, optional
    Foundry Agent (V2) deployment name to invoke. Defaults to
    ``zava-customer-service``.
FOUNDRY_ORCHESTRATOR_DEPLOYMENT : str, optional
    Model deployment bound to the Foundry agent. Used as the ``model``
    parameter on ``responses.create`` — Foundry GA rejects mismatched
    model values when ``agent_reference`` is set. Defaults to
    ``gpt-55-orchestrator``.
LOG_LEVEL : str, optional
    Root logger level. Defaults to ``INFO``.
DEV_MODE : str, optional
    If ``"true"`` (case-insensitive), the app boots even when
    ``FOUNDRY_PROJECT_ENDPOINT`` is missing. Use only for local smoke tests.
FOUNDRY_OPENAI_API_VERSION : str, optional
    Azure OpenAI / Foundry Responses API version. Defaults to empty
    string for Foundry V2 GA, which rejects an explicit ``api-version``
    on its ``/v1`` Responses endpoint. Set this only if you need to pin a
    Preview API version on an older Foundry SDK build.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass

logger = logging.getLogger(__name__)

_DEFAULT_AGENT_NAME = "zava-customer-service"
_DEFAULT_ORCHESTRATOR_DEPLOYMENT = "gpt-55-orchestrator"
_DEFAULT_API_VERSION = ""
_DEV_MODE_PLACEHOLDER_ENDPOINT = "https://dev-mode-placeholder.invalid/api/projects/dev"


@dataclass(frozen=True)
class Settings:
    """Immutable application settings."""

    foundry_project_endpoint: str
    foundry_agent_name: str
    foundry_orchestrator_deployment: str
    foundry_openai_api_version: str
    log_level: str
    dev_mode: bool


def _parse_bool(value: str | None) -> bool:
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load_settings() -> Settings:
    """Load and validate settings from the process environment.

    Raises
    ------
    RuntimeError
        If ``FOUNDRY_PROJECT_ENDPOINT`` is not set and ``DEV_MODE`` is not
        truthy.
    """

    dev_mode = _parse_bool(os.environ.get("DEV_MODE"))
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    agent_name = os.environ.get("FOUNDRY_AGENT_NAME", _DEFAULT_AGENT_NAME)
    orchestrator_deployment = os.environ.get(
        "FOUNDRY_ORCHESTRATOR_DEPLOYMENT", _DEFAULT_ORCHESTRATOR_DEPLOYMENT
    )
    api_version = os.environ.get("FOUNDRY_OPENAI_API_VERSION", _DEFAULT_API_VERSION)
    endpoint = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")

    if not endpoint:
        if not dev_mode:
            raise RuntimeError(
                "FOUNDRY_PROJECT_ENDPOINT is required. Set the environment "
                "variable to your Foundry V2 project endpoint, or set "
                "DEV_MODE=true to start the backend without a Foundry "
                "endpoint for local smoke testing."
            )
        logger.warning(
            "DEV_MODE is enabled and FOUNDRY_PROJECT_ENDPOINT is not set; "
            "using placeholder endpoint. Agent invocations will fail."
        )
        endpoint = _DEV_MODE_PLACEHOLDER_ENDPOINT

    return Settings(
        foundry_project_endpoint=endpoint,
        foundry_agent_name=agent_name,
        foundry_orchestrator_deployment=orchestrator_deployment,
        foundry_openai_api_version=api_version,
        log_level=log_level,
        dev_mode=dev_mode,
    )


# Module-level singleton — evaluated at import time so missing config
# fails fast when ``app.main`` is loaded (e.g., by uvicorn).
settings: Settings = load_settings()

# Configure root logger as early as possible.
logging.basicConfig(
    level=getattr(logging, settings.log_level, logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
