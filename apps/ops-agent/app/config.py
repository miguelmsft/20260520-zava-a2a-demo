"""Configuration for the Zava Ops Agent.

Environment variables:
    AZURE_OPENAI_ENDPOINT      Required at agent runtime. Example:
                               https://my-foundry-resource.openai.azure.com/
    AZURE_OPENAI_DEPLOYMENT    Required at agent runtime. The deployment name
                               of the worker model (no dots), e.g. `gpt-54mini-worker`.
    AZURE_OPENAI_API_VERSION   Optional. Defaults to "2025-03-01-preview".
    DATA_DIR                   Optional. Directory containing the synthetic
                               Zava JSON files. Defaults to `<package>/../data`.

We deliberately use lazy validation: importing `app.config` (or any module
that depends on it) MUST NOT fail when Azure env vars are unset, so that
unit tests, the `agent_card`, and tools can be imported in CI without any
Azure setup. Validation happens only when `get_settings()` is called or
`require_azure()` is invoked (e.g. just before constructing the LLM client).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_API_VERSION = "2025-03-01-preview"


def _default_data_dir() -> Path:
    # apps/ops-agent/app/config.py -> apps/ops-agent/data
    return Path(__file__).resolve().parent.parent / "data"


@dataclass(frozen=True)
class Settings:
    """Resolved runtime settings.

    Note: `azure_openai_endpoint` and `azure_openai_deployment` may be empty
    strings if the corresponding env vars are unset. Callers that need Azure
    must invoke `require_azure()` to get a fail-fast error.
    """

    azure_openai_endpoint: str
    azure_openai_deployment: str
    azure_openai_api_version: str
    data_dir: Path


def get_settings() -> Settings:
    """Build a fresh Settings snapshot from the current environment.

    This is intentionally not cached so that tests can override env vars
    between calls.
    """
    data_dir_env = os.environ.get("DATA_DIR")
    data_dir = Path(data_dir_env) if data_dir_env else _default_data_dir()
    return Settings(
        azure_openai_endpoint=os.environ.get("AZURE_OPENAI_ENDPOINT", ""),
        azure_openai_deployment=os.environ.get("AZURE_OPENAI_DEPLOYMENT", ""),
        azure_openai_api_version=os.environ.get(
            "AZURE_OPENAI_API_VERSION", DEFAULT_API_VERSION
        ),
        data_dir=data_dir,
    )


def require_azure(settings: Settings | None = None) -> Settings:
    """Return settings, raising RuntimeError if Azure env vars are missing.

    Call this immediately before constructing an `AzureChatOpenAI` client.
    Tests and import-time code paths should NOT call this.
    """
    s = settings or get_settings()
    missing = []
    if not s.azure_openai_endpoint:
        missing.append("AZURE_OPENAI_ENDPOINT")
    if not s.azure_openai_deployment:
        missing.append("AZURE_OPENAI_DEPLOYMENT")
    if missing:
        raise RuntimeError(
            "Missing required Azure OpenAI environment variables: "
            + ", ".join(missing)
        )
    return s
