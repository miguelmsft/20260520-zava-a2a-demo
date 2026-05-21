"""Smoke test for the deployed Zava Foundry V2 customer service agent.

Sends one feasibility query, streams the Responses API events, and verifies:

1. Text output is received from the orchestrator.
2. A Code Interpreter file artifact (chart) is produced.
3. At least one A2A hop (``remote_function_call``) to the Ops Agent occurs.
4. **R16 — artifact passthrough:** the A2A tool result is structured JSON
   containing a ``feasibility_score`` field, not an opaque string.

Exit code 0 on full success, 1 if any of (1)-(3) is missing.

Usage::

    python test_agent.py

Required env vars:
- ``FOUNDRY_PROJECT_ENDPOINT``
- ``FOUNDRY_AGENT_NAME`` (default ``zava-customer-service``)
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any, Optional

DEFAULT_AGENT_NAME = "zava-customer-service"
DEFAULT_API_VERSION = "preview"
SAMPLE_QUERY = (
    "Can we fulfill an order for 150 ZP-7000 centrifugal pumps for "
    "CUST-001 by 2026-07-15?"
)


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        print(
            f"ERROR: required environment variable {name!r} is not set.",
            file=sys.stderr,
        )
        sys.exit(2)
    return value


def _get(obj: Any, *names: str, default: Any = None) -> Any:
    """Return the first present attribute/key from ``names``."""
    for name in names:
        if obj is None:
            return default
        if isinstance(obj, dict):
            if name in obj:
                return obj[name]
        elif hasattr(obj, name):
            value = getattr(obj, name)
            if value is not None:
                return value
    return default


def _try_parse_json(value: Any) -> tuple[bool, Any]:
    """Return ``(parsed_ok, parsed_value_or_original)``."""
    if isinstance(value, (dict, list)):
        return True, value
    if isinstance(value, (bytes, bytearray)):
        try:
            value = value.decode("utf-8")
        except UnicodeDecodeError:
            return False, value
    if isinstance(value, str):
        try:
            return True, json.loads(value)
        except (ValueError, TypeError):
            return False, value
    return False, value


def main(argv: Optional[list[str]] = None) -> int:  # noqa: ARG001
    project_endpoint = _require_env("FOUNDRY_PROJECT_ENDPOINT")
    agent_name = os.environ.get("FOUNDRY_AGENT_NAME", DEFAULT_AGENT_NAME)
    api_version = os.environ.get("FOUNDRY_OPENAI_API_VERSION", DEFAULT_API_VERSION)

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

    print(f"Project endpoint : {project_endpoint}")
    print(f"Agent name       : {agent_name}")
    print(f"Query            : {SAMPLE_QUERY}")
    print("-" * 72)

    saw_text = False
    saw_chart = False
    saw_a2a_hop = False
    r16_warning: Optional[str] = None
    chart_file_ids: list[str] = []
    a2a_payloads: list[Any] = []
    text_chunks: list[str] = []

    try:
        with AIProjectClient(
            endpoint=project_endpoint,
            credential=DefaultAzureCredential(),
        ) as project:
            # The Foundry SDK returns a sync `openai.OpenAI` wired to the
            # project's `/openai/v1/` endpoint. Pass api-version via
            # default_query (see Step 12 implementation notes in plan.md).
            openai_client = project.get_openai_client(
                default_query={"api-version": api_version},
            )

            stream = openai_client.responses.create(
                model=agent_name,
                input=SAMPLE_QUERY,
                stream=True,
                extra_body={"agent_reference": {"name": agent_name}},
            )

            for event in stream:
                event_type = _get(event, "type", default="") or ""

                # ---- text deltas ------------------------------------------
                if event_type.endswith("output_text.delta"):
                    delta = _get(event, "delta", default="") or ""
                    if delta:
                        saw_text = True
                        text_chunks.append(delta)
                        sys.stdout.write(delta)
                        sys.stdout.flush()
                    continue

                # ---- output items ----------------------------------------
                if "output_item" in event_type:
                    item = _get(event, "item", default=None)
                    item_type = _get(item, "type", default="") or ""

                    if item_type == "remote_function_call":
                        saw_a2a_hop = True
                        call_id = _get(item, "call_id", "id", default="?")
                        label = _get(item, "label", "name", default="a2a")
                        print(f"\n[a2a_hop] {label} call_id={call_id} ({event_type})")

                        # Look for the tool's output payload — naming varies
                        # across SDK builds; check the common fields.
                        payload = _get(
                            item,
                            "output",
                            "result",
                            "response",
                            "content",
                            default=None,
                        )
                        if payload is not None:
                            a2a_payloads.append(payload)
                        continue

                    if item_type in {"image_file", "image", "file", "code_interpreter_file"}:
                        saw_chart = True
                        file_id = _get(item, "file_id", "id", default="?")
                        chart_file_ids.append(str(file_id))
                        print(f"\n[chart] file_id={file_id} item_type={item_type}")
                        continue

                    if item_type in {"tool_call", "code_interpreter_call"}:
                        name = _get(item, "name", default=item_type)
                        print(f"\n[tool_call] {name} ({event_type})")
                        continue

                    print(f"\n[output_item] item_type={item_type} ({event_type})")
                    continue

                # ---- lifecycle / error -----------------------------------
                if event_type in {"response.completed", "response.done"}:
                    print(f"\n[done] {event_type}")
                    continue
                if "error" in event_type:
                    print(f"\n[error] {event_type}: {_get(event, 'message', default=event)}")
                    continue

                # Quietly note other event types for debugging.
                if os.environ.get("TEST_AGENT_VERBOSE"):
                    print(f"\n[event] {event_type}")
    except Exception as exc:  # noqa: BLE001
        print(
            f"\nERROR: exception while streaming: {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return 1

    print()
    print("=" * 72)
    print("Summary")
    print("=" * 72)
    print(f"  {'✓' if saw_text else '✗'} Text output received "
          f"({sum(len(c) for c in text_chunks)} chars)")
    print(f"  {'✓' if saw_chart else '✗'} Code Interpreter chart artifact "
          f"({len(chart_file_ids)} file(s): {chart_file_ids or '—'})")
    print(f"  {'✓' if saw_a2a_hop else '✗'} A2A delegation (remote_function_call) "
          f"({len(a2a_payloads)} payload(s))")

    # ---- R16 artifact-passthrough check --------------------------------
    if a2a_payloads:
        parsed_ok_any = False
        has_score = False
        for payload in a2a_payloads:
            ok, parsed = _try_parse_json(payload)
            if ok:
                parsed_ok_any = True
                if isinstance(parsed, dict) and "feasibility_score" in parsed:
                    has_score = True
                    break
                # Sometimes the payload nests a `content` list of parts.
                if isinstance(parsed, dict):
                    for v in parsed.values():
                        if isinstance(v, dict) and "feasibility_score" in v:
                            has_score = True
                            break
        if not parsed_ok_any:
            r16_warning = (
                "⚠ R16: A2A artifact arrived as opaque string, not structured "
                "JSON. The orchestrator cannot reason over fields like "
                "`feasibility_score`. Update system_prompt.md to instruct the "
                "agent to JSON-parse tool output, or file a Foundry SDK issue."
            )
        elif not has_score:
            r16_warning = (
                "⚠ R16: A2A artifact parsed as JSON but no `feasibility_score` "
                "field found. Confirm the Ops Agent contract matches §A.5."
            )
        else:
            print("  ✓ R16: A2A payload parsed as JSON with `feasibility_score`.")
    elif saw_a2a_hop:
        r16_warning = (
            "⚠ R16: A2A hop occurred but no payload was captured from the "
            "stream events. Tool-output passthrough cannot be verified."
        )

    if r16_warning:
        print()
        print(r16_warning)

    print()
    all_ok = saw_text and saw_chart and saw_a2a_hop
    if all_ok:
        print("✓ Smoke test PASSED.")
        return 0
    print("✗ Smoke test FAILED — see ✗ markers above.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
