"""LangChain tools that read synthetic Zava operations data.

Tools load the JSON data files once at module import (small dataset, single-
pod deployment, immutable for the demo) and serve queries from in-memory
dicts. Each tool returns a structured dict and gracefully handles the
"not found" case rather than raising — so the LLM can reason about it.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from langchain_core.tools import tool

from .config import get_settings


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


@lru_cache(maxsize=1)
def _data() -> dict[str, Any]:
    """Load all four JSON data files. Cached at first access."""
    data_dir = get_settings().data_dir
    return {
        "inventory": _load_json(data_dir / "inventory.json"),
        "production_schedule": _load_json(data_dir / "production_schedule.json"),
        "order_book": _load_json(data_dir / "order_book.json"),
        "customers": _load_json(data_dir / "customers.json"),
    }


def reset_cache() -> None:
    """Clear cached data (used by tests that change DATA_DIR)."""
    _data.cache_clear()


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


@tool
def lookup_inventory(sku: str) -> dict:
    """Look up current inventory for a Zava SKU.

    Args:
        sku: The Zava SKU (e.g. ``ZP-7000``).

    Returns:
        A dict with `found` (bool), `sku`, and on success the inventory
        record (on_hand, allocated, reserved, available, reorder_point,
        supplier_lead_time_days, unit_cost, name, category).
    """
    items = _data()["inventory"].get("items", [])
    for item in items:
        if item.get("sku") == sku:
            return {"found": True, "sku": sku, **item}
    return {"found": False, "sku": sku, "message": f"SKU {sku} not found in inventory"}


@tool
def lookup_production_schedule(sku: str, start_date: str, end_date: str) -> dict:
    """Look up production schedule slots for a SKU within a date window.

    Returns the machines capable of producing the SKU and their available
    production slots whose date falls within [start_date, end_date]
    (inclusive, ISO ``YYYY-MM-DD`` strings, lexicographic compare).

    Args:
        sku: Zava SKU to produce.
        start_date: Inclusive lower bound, ``YYYY-MM-DD``.
        end_date: Inclusive upper bound, ``YYYY-MM-DD``.

    Returns:
        A dict with `found` (bool), `sku`, `machines` (list of capable
        machines with their filtered slots), `total_capacity_in_window`
        (sum of available_units across all matching slots).
    """
    machines = _data()["production_schedule"].get("machines", [])
    capable: list[dict[str, Any]] = []
    total_capacity = 0
    for m in machines:
        if sku not in m.get("sku_capabilities", []):
            continue
        slots_in_window = [
            s
            for s in m.get("available_slots", [])
            if start_date <= s.get("date", "") <= end_date
        ]
        capacity = sum(int(s.get("available_units", 0)) for s in slots_in_window)
        capable.append(
            {
                "machine_id": m.get("machine_id"),
                "name": m.get("name"),
                "capacity_per_day": m.get("capacity_per_day"),
                "current_load_pct": m.get("current_load_pct"),
                "scheduled_maintenance": m.get("scheduled_maintenance"),
                "slots": slots_in_window,
                "capacity_in_window": capacity,
            }
        )
        total_capacity += capacity

    if not capable:
        return {
            "found": False,
            "sku": sku,
            "machines": [],
            "total_capacity_in_window": 0,
            "message": f"No machines capable of producing {sku}",
        }
    return {
        "found": True,
        "sku": sku,
        "start_date": start_date,
        "end_date": end_date,
        "machines": capable,
        "total_capacity_in_window": total_capacity,
    }


@tool
def lookup_order_book(sku: str) -> dict:
    """List open (non-shipped, non-cancelled) orders for a Zava SKU.

    Args:
        sku: Zava SKU.

    Returns:
        A dict with `sku`, `count`, `orders` (list of order records).
        Always returns a result (empty `orders` list when none).
    """
    orders = _data()["order_book"].get("orders", [])
    open_states = {"confirmed", "in_production"}
    matching = [
        o
        for o in orders
        if o.get("sku") == sku and o.get("status") in open_states
    ]
    return {
        "sku": sku,
        "count": len(matching),
        "orders": matching,
    }


@tool
def lookup_customer(customer_id: str) -> dict:
    """Look up a Zava customer profile by ID.

    Args:
        customer_id: Customer ID, e.g. ``CUST-001``.

    Returns:
        A dict with `found` (bool), `customer_id`, and on success the
        customer record (name, priority_tier, region, payment_terms,
        annual_volume).
    """
    customers = _data()["customers"].get("customers", [])
    for c in customers:
        if c.get("customer_id") == customer_id:
            return {"found": True, "customer_id": customer_id, **c}
    return {
        "found": False,
        "customer_id": customer_id,
        "message": f"Customer {customer_id} not found",
    }


# Convenience list for binding to the LLM.
ALL_TOOLS = [
    lookup_inventory,
    lookup_production_schedule,
    lookup_order_book,
    lookup_customer,
]
