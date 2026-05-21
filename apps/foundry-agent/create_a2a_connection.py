"""Provision the outbound A2A connection from Foundry to the AKS Ops Agent.

Portal-first, SDK-fallback
--------------------------
A2A connections in Foundry V2 are **portal-created** in the current Preview
(see research/2026-05-20-foundry-agents.md §5). This script:

1. Prints step-by-step Foundry portal instructions on stdout, with the
   API key value boxed prominently for copy/paste.
2. Optimistically attempts ``project.connections.create(...)`` as an SDK
   fallback. The call is expected to fail in current Preview — failure is
   reported as informational and is **not** an error.

Run with ``--verify`` after completing the portal steps to confirm the
connection is wired up correctly.

Usage
-----
    python create_a2a_connection.py            # print instructions + SDK try
    python create_a2a_connection.py --verify   # confirm connection exists

Required environment variables (see ``.env.example``):

- ``FOUNDRY_PROJECT_ENDPOINT``
- ``OPS_AGENT_ENDPOINT``
- ``OPS_AGENT_API_KEY``      (required in default mode; not needed for --verify)
- ``A2A_CONNECTION_NAME``    (optional, default ``ops-agent-a2a``)
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Optional

DEFAULT_A2A_CONNECTION = "ops-agent-a2a"


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create the Foundry → AKS Ops Agent A2A connection. "
            "Portal-first; SDK fallback is attempted but expected to fail "
            "in current Foundry V2 Preview."
        )
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Skip instructions and look up the existing connection via SDK.",
    )
    return parser.parse_args(argv)


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        print(
            f"ERROR: required environment variable {name!r} is not set.",
            file=sys.stderr,
        )
        sys.exit(2)
    return value


def _print_boxed_secret(api_key: str) -> None:
    label = "x-api-key value (copy into Foundry portal — KEEP SECRET):"
    width = max(len(label), len(api_key)) + 4
    bar = "+" + "-" * (width - 2) + "+"
    print(bar)
    print("| " + label.ljust(width - 4) + " |")
    print("| " + api_key.ljust(width - 4) + " |")
    print(bar)
    print("⚠  Do NOT commit this value. Do NOT paste it into chat or tickets.")


def _print_portal_instructions(
    connection_name: str, ops_endpoint: str, api_key: str
) -> None:
    print("=" * 72)
    print("Foundry portal — create outbound A2A connection (CANONICAL PATH)")
    print("=" * 72)
    print()
    print("  1. Open the Foundry portal and confirm the 'New Foundry' toggle is ON")
    print("     (project-based experience, NOT Foundry Classic / Hubs).")
    print(f"  2. Navigate to your project → Connections → '+ Add connection'.")
    print("  3. Choose connection type: 'Agent (A2A)' — also labelled")
    print("     'Agent2Agent (A2A)' under the 'Custom' tab on some portal builds.")
    print(f"  4. Connection name: {connection_name}")
    print(f"  5. Endpoint URL:    {ops_endpoint}")
    print("  6. Authentication:  API key")
    print("  7. Header name:     x-api-key")
    print("  8. Header value:    (paste from the boxed value below)")
    print("  9. Save the connection, then re-run this script with --verify to")
    print("     confirm it is wired up:")
    print("         python create_a2a_connection.py --verify")
    print()
    _print_boxed_secret(api_key)
    print()


def _attempt_sdk_fallback(
    project_endpoint: str,
    connection_name: str,
    ops_endpoint: str,
    api_key: str,
) -> None:
    """Best-effort SDK creation. Always returns; never raises."""
    print("-" * 72)
    print("Attempting SDK fallback (best-effort; portal-only in current Preview)...")
    print("-" * 72)
    try:
        from azure.ai.projects import AIProjectClient
        from azure.identity import DefaultAzureCredential
    except ImportError as exc:
        print(
            f"ℹ SDK fallback skipped — azure-ai-projects not importable ({exc})."
        )
        return

    try:
        with AIProjectClient(
            endpoint=project_endpoint,
            credential=DefaultAzureCredential(),
        ) as project:
            project.connections.create(
                connection_type="A2A",
                name=connection_name,
                endpoint=ops_endpoint,
                auth={
                    "type": "api_key",
                    "header_name": "x-api-key",
                    "header_value": api_key,
                },
            )
        print(
            "✓ SDK fallback succeeded — connection created programmatically. "
            "You may skip the portal steps above."
        )
    except Exception as exc:  # noqa: BLE001
        print(
            "ℹ SDK fallback failed (expected — A2A connections are portal-only "
            "in current Foundry V2 Preview). Please complete the manual portal "
            "steps above."
        )
        print(f"  Error: {type(exc).__name__}: {exc}")


def _verify(project_endpoint: str, connection_name: str) -> int:
    try:
        from azure.ai.projects import AIProjectClient
        from azure.identity import DefaultAzureCredential
    except ImportError as exc:
        print(
            f"ERROR: azure-ai-projects not importable ({exc}). "
            "Run `pip install -e .` in apps/foundry-agent/.",
            file=sys.stderr,
        )
        return 2

    try:
        with AIProjectClient(
            endpoint=project_endpoint,
            credential=DefaultAzureCredential(),
        ) as project:
            connection = project.connections.get(name=connection_name)
    except Exception as exc:  # noqa: BLE001
        print(
            f"✗ Connection {connection_name!r} NOT FOUND or inaccessible.\n"
            f"  {type(exc).__name__}: {exc}\n\n"
            "  Make sure you completed the portal steps and that the calling "
            "identity has 'Azure AI User' or higher on the project.",
            file=sys.stderr,
        )
        return 1

    print(f"✓ Connection {connection_name!r} found.")
    for field in ("name", "id", "endpoint", "auth_type", "type", "target"):
        value = getattr(connection, field, None)
        if value is not None:
            print(f"    {field:12s}: {value}")
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    args = _parse_args(argv)

    project_endpoint = _require_env("FOUNDRY_PROJECT_ENDPOINT")
    connection_name = os.environ.get("A2A_CONNECTION_NAME", DEFAULT_A2A_CONNECTION)

    if args.verify:
        return _verify(project_endpoint, connection_name)

    ops_endpoint = _require_env("OPS_AGENT_ENDPOINT")
    api_key = _require_env("OPS_AGENT_API_KEY")

    _print_portal_instructions(connection_name, ops_endpoint, api_key)
    _attempt_sdk_fallback(project_endpoint, connection_name, ops_endpoint, api_key)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
