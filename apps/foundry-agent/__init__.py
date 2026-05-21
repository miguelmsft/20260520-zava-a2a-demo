"""Zava Foundry V2 Customer Service Agent setup scripts (Step 11).

This package contains operator-run scripts that provision the Foundry side
of the demo:

- `setup_agent.py` — create / version the `zava-customer-service` prompt
  agent with Code Interpreter + A2APreviewTool.
- `create_a2a_connection.py` — print portal instructions and attempt the
  optional SDK fallback to create the outbound A2A connection.
- `test_agent.py` — smoke-test the deployed agent end-to-end.
"""
