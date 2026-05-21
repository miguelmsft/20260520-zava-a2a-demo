"""Create or update the Zava Customer Service prompt agent on Foundry V2.

Idempotent: ``project.agents.create_version`` creates a new immutable version
under the same logical ``agent_name`` on every run, so it is safe to re-run
after editing ``system_prompt.md``.

Usage
-----
Populate environment variables (see ``.env.example``):

- ``FOUNDRY_PROJECT_ENDPOINT`` — required
- ``FOUNDRY_ORCHESTRATOR_DEPLOYMENT`` — required (model deployment name)
- ``A2A_CONNECTION_NAME`` — optional, default ``ops-agent-a2a``
- ``FOUNDRY_AGENT_NAME`` — optional, default ``zava-customer-service``

Then::

    python setup_agent.py                # create / update the agent
    python setup_agent.py --dry-run      # print what would happen
    python setup_agent.py --verbose      # extra logging

Prerequisites: an A2A connection named ``A2A_CONNECTION_NAME`` must already
exist in the Foundry project — create it via ``create_a2a_connection.py``
(portal-first).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path
from typing import Optional

DEFAULT_A2A_CONNECTION = "ops-agent-a2a"
DEFAULT_AGENT_NAME = "zava-customer-service"
SYSTEM_PROMPT_PATH = Path(__file__).parent / "system_prompt.md"

logger = logging.getLogger("setup_agent")


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create/update the Zava Foundry V2 customer service agent."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would happen without contacting Foundry.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable DEBUG logging.",
    )
    return parser.parse_args(argv)


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        print(
            f"ERROR: required environment variable {name!r} is not set.\n"
            "       See apps/foundry-agent/.env.example for the full list.",
            file=sys.stderr,
        )
        sys.exit(2)
    return value


def _load_system_prompt() -> str:
    if not SYSTEM_PROMPT_PATH.exists():
        print(
            f"ERROR: system prompt not found at {SYSTEM_PROMPT_PATH}.",
            file=sys.stderr,
        )
        sys.exit(2)
    text = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()
    if not text:
        print(
            f"ERROR: system prompt at {SYSTEM_PROMPT_PATH} is empty.",
            file=sys.stderr,
        )
        sys.exit(2)
    return text


def main(argv: Optional[list[str]] = None) -> int:
    args = _parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    project_endpoint = _require_env("FOUNDRY_PROJECT_ENDPOINT")
    orchestrator_deployment = _require_env("FOUNDRY_ORCHESTRATOR_DEPLOYMENT")
    a2a_connection_name = os.environ.get("A2A_CONNECTION_NAME", DEFAULT_A2A_CONNECTION)
    agent_name = os.environ.get("FOUNDRY_AGENT_NAME", DEFAULT_AGENT_NAME)

    instructions = _load_system_prompt()

    print("=" * 72)
    print("Zava Foundry V2 — Customer Service Agent setup")
    print("=" * 72)
    print(f"  Project endpoint    : {project_endpoint}")
    print(f"  Agent name          : {agent_name}")
    print(f"  Model deployment    : {orchestrator_deployment}")
    print(f"  A2A connection name : {a2a_connection_name}")
    print(f"  System prompt       : {SYSTEM_PROMPT_PATH} ({len(instructions)} chars)")
    print(f"  Tools               : CodeInterpreterTool, A2APreviewTool")
    print("=" * 72)

    if args.dry_run:
        print("\n--dry-run set: skipping AIProjectClient calls. Nothing was created.")
        return 0

    # Imports deferred so --dry-run works without the SDK fully wired up.
    try:
        from azure.ai.projects import AIProjectClient
        from azure.ai.projects.models import (
            A2APreviewTool,
            CodeInterpreterTool,
            PromptAgentDefinition,
        )
        from azure.identity import DefaultAzureCredential
    except ImportError as exc:  # pragma: no cover — environment problem
        print(
            f"ERROR: failed to import azure-ai-projects / azure-identity ({exc}).\n"
            "       Run `pip install -e .` in apps/foundry-agent/.",
            file=sys.stderr,
        )
        return 2

    try:
        with AIProjectClient(
            endpoint=project_endpoint,
            credential=DefaultAzureCredential(),
        ) as project:
            logger.info("Looking up A2A connection %r ...", a2a_connection_name)
            try:
                connection = project.connections.get(name=a2a_connection_name)
            except Exception as exc:  # noqa: BLE001
                print(
                    f"\nERROR: A2A connection {a2a_connection_name!r} not found "
                    f"in project.\n"
                    f"       Underlying error: {exc}\n\n"
                    "       Create it first by running:\n"
                    "           python create_a2a_connection.py\n"
                    "       (Follow the printed portal steps; A2A connections are "
                    "currently portal-only in Foundry V2 Preview.)",
                    file=sys.stderr,
                )
                return 1

            logger.info("Found connection id=%s", getattr(connection, "id", "?"))

            tools = [
                CodeInterpreterTool(),
                A2APreviewTool(project_connection_id=connection.id),
            ]

            definition = PromptAgentDefinition(
                model=orchestrator_deployment,
                instructions=instructions,
                tools=tools,
            )

            logger.info("Creating new version for agent %r ...", agent_name)
            agent = project.agents.create_version(
                agent_name=agent_name,
                definition=definition,
            )
    except Exception as exc:  # noqa: BLE001
        print(
            f"\nERROR: failed to create/update agent {agent_name!r}.\n"
            f"       {type(exc).__name__}: {exc}\n\n"
            "Troubleshooting checklist:\n"
            "  1. RBAC: the calling identity needs 'Azure AI User' (or higher) "
            "on the Foundry resource AND project.\n"
            "  2. Model deployment: confirm "
            f"{orchestrator_deployment!r} exists in the project (Bicep output "
            "`orchestratorDeploymentName`).\n"
            "  3. A2A connection: confirm "
            f"{a2a_connection_name!r} exists (re-run "
            "`python create_a2a_connection.py --verify`).\n"
            "  4. Endpoint: confirm FOUNDRY_PROJECT_ENDPOINT points at the "
            "Foundry V2 project, not the account root.",
            file=sys.stderr,
        )
        return 1

    print("\n✓ Agent created / updated successfully.")
    print(f"    Agent name        : {getattr(agent, 'name', agent_name)}")
    print(f"    Agent version     : {getattr(agent, 'version', '?')}")
    print(f"    Agent ID          : {getattr(agent, 'id', '?')}")
    print(f"    Model deployment  : {orchestrator_deployment}")
    print(f"    Tools             : CodeInterpreterTool, A2APreviewTool")
    print()
    print("Next step: smoke-test the agent with `python test_agent.py`.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
