"""Provision the outbound A2A connection from Foundry to the AKS Ops Agent.

Three creation paths (tried in order)
-------------------------------------
A2A connections in Foundry V2 GA can be created three ways. This script
attempts them in order of preference:

1. **ARM REST PUT** (preferred — fully automatic).
   The data-plane Python SDK (``azure-ai-projects`` 2.1.x) does **not**
   expose ``connections.create``. The management plane does:
   ``PUT /subscriptions/.../accounts/.../projects/.../connections/{name}``
   at api-version ``2025-06-01`` with ``category=CustomKeys`` and
   ``metadata.a2a_subtype=agent`` creates an A2A-compatible connection.
   Requires ``Cognitive Services Contributor`` (or higher) on the account.

2. **SDK fallback** (best-effort; expected to fail on current GA).
   Wrapped in a try/except — used for forward-compat with future SDKs.

3. **Manual portal instructions** (printed on stdout as a fallback).
   Step-by-step instructions for operators without ARM write access.

Run with ``--verify`` after creation to confirm the connection is wired up.

Usage
-----
    python create_a2a_connection.py            # try ARM → SDK → print portal steps
    python create_a2a_connection.py --verify   # confirm connection exists
    python create_a2a_connection.py --portal-only   # skip ARM/SDK, just print steps

Required environment variables (see ``.env.example``):

- ``FOUNDRY_PROJECT_ENDPOINT``
- ``OPS_AGENT_ENDPOINT``
- ``OPS_AGENT_API_KEY``      (required in create mode; not needed for --verify)
- ``A2A_CONNECTION_NAME``    (optional, default ``ops-agent-a2a``)

The script auto-derives the ARM resource path from
``FOUNDRY_PROJECT_ENDPOINT`` (e.g. ``https://foundry-X.services.ai.azure.com/api/projects/Y``)
plus the current ``az`` subscription and the resource group hosting the
account. Set ``AZ_RESOURCE_GROUP`` / ``AZ_SUBSCRIPTION_ID`` to override.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from typing import Optional
from urllib import error as urllib_error
from urllib import request as urllib_request

# Force UTF-8 on stdout/stderr so checkmark/cross glyphs don't crash on
# Windows consoles using cp1252 (Python 3.7+).
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except (AttributeError, OSError):
        pass

DEFAULT_A2A_CONNECTION = "ops-agent-a2a"
ARM_API_VERSION = "2025-06-01"


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create the Foundry → AKS Ops Agent A2A connection. "
            "Tries ARM REST PUT first (automatic), then SDK, then prints "
            "portal instructions as a fallback."
        )
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Skip creation and look up the existing connection via SDK.",
    )
    parser.add_argument(
        "--portal-only",
        action="store_true",
        help="Skip ARM/SDK attempts and only print portal instructions.",
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
) -> bool:
    """Best-effort SDK creation. Returns True on success, False otherwise."""
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
        return False

    try:
        with AIProjectClient(
            endpoint=project_endpoint,
            credential=DefaultAzureCredential(),
        ) as project:
            project.connections.create(  # type: ignore[attr-defined]
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
        return True
    except Exception as exc:  # noqa: BLE001
        print(
            "ℹ SDK fallback failed (expected — A2A connections are portal-only "
            "in current Foundry V2 Preview / GA SDK gap)."
        )
        print(f"  Error: {type(exc).__name__}: {exc}")
        return False


def _parse_account_from_endpoint(project_endpoint: str) -> tuple[Optional[str], Optional[str]]:
    """Extract (account_name, project_name) from a Foundry project endpoint.

    Accepts e.g. ``https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility``.
    """
    # Account name = first dotted segment of the host
    host_match = re.match(r"https?://([^.]+)\.services\.ai\.azure\.com", project_endpoint)
    project_match = re.search(r"/projects/([^/?#]+)", project_endpoint)
    account = host_match.group(1) if host_match else None
    project = project_match.group(1) if project_match else None
    return account, project


def _run_az(args: list[str]) -> Optional[str]:
    """Run an ``az`` CLI command and return stdout, or None on failure."""
    az = shutil.which("az") or shutil.which("az.cmd")
    if not az:
        return None
    try:
        result = subprocess.run(
            [az] + args,
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"  az command failed to launch: {exc}", file=sys.stderr)
        return None
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        if stderr:
            print(f"  az returned non-zero: {stderr}", file=sys.stderr)
        return None
    return (result.stdout or "").strip()


def _resolve_arm_path(account_name: str) -> Optional[tuple[str, str]]:
    """Look up the (subscription_id, resource_group) hosting the account."""
    subscription = os.environ.get("AZ_SUBSCRIPTION_ID") or _run_az(
        ["account", "show", "--query", "id", "-o", "tsv"]
    )
    if not subscription:
        print(
            "  Could not determine subscription id. Set AZ_SUBSCRIPTION_ID or run "
            "`az login`.",
            file=sys.stderr,
        )
        return None
    resource_group = os.environ.get("AZ_RESOURCE_GROUP") or _run_az(
        [
            "cognitiveservices",
            "account",
            "list",
            "--query",
            f"[?name=='{account_name}'].resourceGroup | [0]",
            "-o",
            "tsv",
        ]
    )
    if not resource_group:
        print(
            f"  Could not locate resource group hosting Foundry account "
            f"{account_name!r}. Set AZ_RESOURCE_GROUP or pass it via env.",
            file=sys.stderr,
        )
        return None
    return subscription, resource_group


def _attempt_arm_rest_create(
    project_endpoint: str,
    connection_name: str,
    ops_endpoint: str,
    api_key: str,
) -> bool:
    """Create the A2A connection via direct ARM REST PUT.

    This is the **preferred** path. The data-plane SDK (azure-ai-projects 2.1.x)
    does not expose connections.create; the management plane does.
    """
    print("-" * 72)
    print("Attempting ARM REST create (preferred path)...")
    print("-" * 72)

    account, project = _parse_account_from_endpoint(project_endpoint)
    if not account or not project:
        print(
            "  Could not parse Foundry account/project from "
            f"FOUNDRY_PROJECT_ENDPOINT={project_endpoint!r}. Expected form: "
            "https://<account>.services.ai.azure.com/api/projects/<project>.",
            file=sys.stderr,
        )
        return False

    arm_path = _resolve_arm_path(account)
    if not arm_path:
        return False
    subscription_id, resource_group = arm_path

    token = _run_az(
        [
            "account",
            "get-access-token",
            "--resource",
            "https://management.azure.com/",
            "--query",
            "accessToken",
            "-o",
            "tsv",
        ]
    )
    if not token:
        print("  Could not obtain ARM access token. Run `az login`.", file=sys.stderr)
        return False

    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/resourceGroups/{resource_group}"
        f"/providers/Microsoft.CognitiveServices/accounts/{account}"
        f"/projects/{project}/connections/{connection_name}"
        f"?api-version={ARM_API_VERSION}"
    )
    body = {
        "properties": {
            "category": "CustomKeys",
            "target": ops_endpoint,
            "authType": "CustomKeys",
            "credentials": {"keys": {"x-api-key": api_key}},
            "metadata": {"a2a_subtype": "agent"},
        }
    }
    payload = json.dumps(body).encode("utf-8")
    req = urllib_request.Request(
        url=url,
        data=payload,
        method="PUT",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib_request.urlopen(req, timeout=30) as resp:
            status = resp.getcode()
            resp.read()
    except urllib_error.HTTPError as exc:
        detail = (exc.read() or b"").decode("utf-8", errors="replace")
        print(
            f"  ARM REST returned {exc.code} {exc.reason}: {detail[:400]}",
            file=sys.stderr,
        )
        return False
    except urllib_error.URLError as exc:
        print(f"  ARM REST network error: {exc.reason}", file=sys.stderr)
        return False

    if 200 <= status < 300:
        print(
            f"✓ ARM REST create succeeded — connection {connection_name!r} "
            f"created (HTTP {status})."
        )
        print(
            f"  Path: subscriptions/{subscription_id}/resourceGroups/{resource_group}"
            f"/.../accounts/{account}/projects/{project}/connections/{connection_name}"
        )
        return True

    print(f"  Unexpected ARM REST status {status}.", file=sys.stderr)
    return False


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

    if args.portal_only:
        _print_portal_instructions(connection_name, ops_endpoint, api_key)
        return 0

    if _attempt_arm_rest_create(project_endpoint, connection_name, ops_endpoint, api_key):
        print()
        print("Next: run `python create_a2a_connection.py --verify` to confirm.")
        return 0

    if _attempt_sdk_fallback(project_endpoint, connection_name, ops_endpoint, api_key):
        print()
        print("Next: run `python create_a2a_connection.py --verify` to confirm.")
        return 0

    print()
    print("Automated paths unavailable. Falling back to manual portal steps.")
    print()
    _print_portal_instructions(connection_name, ops_endpoint, api_key)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
