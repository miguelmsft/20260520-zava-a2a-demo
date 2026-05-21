"""Unit tests for app.tools — all read from the real synthetic data files."""

from __future__ import annotations

from app.tools import (
    lookup_customer,
    lookup_inventory,
    lookup_order_book,
    lookup_production_schedule,
    reset_cache,
)


def setup_function() -> None:
    # Tests share the same cached data, but reset to ensure isolation.
    reset_cache()


# ---- lookup_inventory --------------------------------------------------------


def test_lookup_inventory_known_sku():
    result = lookup_inventory.invoke({"sku": "ZP-7000"})
    assert result["found"] is True
    assert result["sku"] == "ZP-7000"
    assert result["name"] == "Industrial Centrifugal Pump"
    assert result["available"] == 25
    assert result["supplier_lead_time_days"] == 21


def test_lookup_inventory_unknown_sku():
    result = lookup_inventory.invoke({"sku": "ZX-9999"})
    assert result["found"] is False
    assert result["sku"] == "ZX-9999"
    assert "not found" in result["message"].lower()


# ---- lookup_production_schedule ----------------------------------------------


def test_lookup_production_schedule_known_sku_in_window():
    result = lookup_production_schedule.invoke(
        {"sku": "ZP-7000", "start_date": "2026-05-21", "end_date": "2026-06-20"}
    )
    assert result["found"] is True
    assert result["sku"] == "ZP-7000"
    assert len(result["machines"]) >= 1
    # CNC-01 is capable of ZP-7000 per the synthetic data.
    machine_ids = [m["machine_id"] for m in result["machines"]]
    assert "CNC-01" in machine_ids
    assert result["total_capacity_in_window"] > 0
    # Every returned slot must fall in [start, end]
    for m in result["machines"]:
        for s in m["slots"]:
            assert "2026-05-21" <= s["date"] <= "2026-06-20"


def test_lookup_production_schedule_no_capable_machine():
    result = lookup_production_schedule.invoke(
        {"sku": "ZX-9999", "start_date": "2026-05-21", "end_date": "2026-12-31"}
    )
    assert result["found"] is False
    assert result["machines"] == []
    assert result["total_capacity_in_window"] == 0


def test_lookup_production_schedule_window_outside_slots():
    # Window before any slot dates -> capable machines but zero capacity
    result = lookup_production_schedule.invoke(
        {"sku": "ZP-7000", "start_date": "2020-01-01", "end_date": "2020-01-31"}
    )
    assert result["found"] is True
    assert result["total_capacity_in_window"] == 0
    for m in result["machines"]:
        assert m["slots"] == []


# ---- lookup_order_book -------------------------------------------------------


def test_lookup_order_book_returns_open_orders():
    result = lookup_order_book.invoke({"sku": "ZP-7000"})
    assert result["sku"] == "ZP-7000"
    assert result["count"] == len(result["orders"])
    for o in result["orders"]:
        assert o["sku"] == "ZP-7000"
        assert o["status"] in {"confirmed", "in_production"}


def test_lookup_order_book_unknown_sku_returns_empty():
    result = lookup_order_book.invoke({"sku": "ZX-9999"})
    assert result["sku"] == "ZX-9999"
    assert result["count"] == 0
    assert result["orders"] == []


# ---- lookup_customer ---------------------------------------------------------


def test_lookup_customer_known_id():
    result = lookup_customer.invoke({"customer_id": "CUST-001"})
    assert result["found"] is True
    assert result["customer_id"] == "CUST-001"
    assert result["name"] == "Apex Hydraulics"
    assert result["priority_tier"] == "platinum"


def test_lookup_customer_unknown_id():
    result = lookup_customer.invoke({"customer_id": "CUST-999"})
    assert result["found"] is False
    assert result["customer_id"] == "CUST-999"
    assert "not found" in result["message"].lower()
