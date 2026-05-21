"""Unit tests for app.feasibility.compute_feasibility — pure logic, no IO."""

from __future__ import annotations

from datetime import date, timedelta

from app.feasibility import compute_feasibility


def _today_plus(days: int) -> str:
    return (date.today() + timedelta(days=days)).strftime("%Y-%m-%d")


# Common fixtures -------------------------------------------------------------

INV_AMPLE = {
    "found": True,
    "sku": "ZP-7000",
    "name": "Industrial Centrifugal Pump",
    "on_hand": 500,
    "allocated": 0,
    "reserved": 0,
    "available": 500,
    "reorder_point": 50,
    "supplier_lead_time_days": 14,
}

INV_MEDIUM = {
    "found": True,
    "sku": "ZP-7000",
    "on_hand": 60,
    "allocated": 10,
    "reserved": 5,
    "available": 25,
    "reorder_point": 20,
    "supplier_lead_time_days": 21,
}

INV_TINY = {
    "found": True,
    "sku": "ZM-3300",
    "on_hand": 14,
    "allocated": 7,
    "reserved": 2,
    "available": 5,
    "reorder_point": 10,
    "supplier_lead_time_days": 60,  # too long to count as pipeline
}

CUST_PLATINUM = {
    "found": True,
    "customer_id": "CUST-001",
    "name": "Apex Hydraulics",
    "priority_tier": "platinum",
}

CUST_STANDARD = {
    "found": True,
    "customer_id": "CUST-008",
    "name": "Heartland AgriTech",
    "priority_tier": "standard",
}


# ---- 1. Sufficient inventory: score 1.0, can_fulfill, no late ---------------


def test_sufficient_inventory_returns_score_one():
    result = compute_feasibility(
        inventory=INV_AMPLE,
        production_slots=[],
        orders=[],
        customer=CUST_STANDARD,
        quantity=10,
        target_date=_today_plus(30),
    )
    assert result["can_fulfill"] is True
    assert result["feasibility_score"] == 1.0
    assert result["available_inventory"] == 500
    assert result["days_late"] == 0
    assert result["earliest_promise_date"] == date.today().strftime("%Y-%m-%d")


# ---- 2. Partial feasibility: score in (0,1), earliest_promise_date set ------


def test_partial_via_production_capacity():
    target = _today_plus(45)
    slots = [
        {"date": _today_plus(10), "available_units": 5},
        {"date": _today_plus(20), "available_units": 10},
        {"date": _today_plus(30), "available_units": 20},
    ]
    result = compute_feasibility(
        inventory=INV_MEDIUM,
        production_slots=slots,
        orders=[],
        customer=CUST_STANDARD,
        quantity=60,  # 25 inv + 35 production = 60 fulfillable
        target_date=target,
    )
    assert result["available_inventory"] == 25
    assert result["production_capacity_by_date"] == 35
    assert result["total_fulfillable"] >= 60  # plus supplier_pipeline
    assert result["can_fulfill"] is True
    # earliest_promise_date should be a real future date, not today
    assert result["earliest_promise_date"] > date.today().strftime("%Y-%m-%d")


# ---- 3. Infeasible: score < 1, can_fulfill False ----------------------------


def test_infeasible_request_score_below_one():
    target = _today_plus(7)  # too soon for supplier lead time of 60 days
    result = compute_feasibility(
        inventory=INV_TINY,
        production_slots=[
            {"date": _today_plus(3), "available_units": 1},
        ],
        orders=[],
        customer=CUST_STANDARD,
        quantity=100,
        target_date=target,
    )
    assert result["can_fulfill"] is False
    assert 0.0 <= result["feasibility_score"] < 1.0
    assert result["total_fulfillable"] < 100
    # Long supplier lead time should be flagged
    assert any(
        "lead time" in r.lower() for r in result["risk_factors"]
    )


# ---- 4. Priority customer impact on reserved inventory ----------------------


def test_platinum_customer_can_use_reserved_stock():
    """Platinum-tier customer should pull from `reserved` (gold+ threshold)."""
    platinum_result = compute_feasibility(
        inventory=INV_MEDIUM,
        production_slots=[],
        orders=[],
        customer=CUST_PLATINUM,
        quantity=30,
        target_date=_today_plus(30),
    )
    standard_result = compute_feasibility(
        inventory=INV_MEDIUM,
        production_slots=[],
        orders=[],
        customer=CUST_STANDARD,
        quantity=30,
        target_date=_today_plus(30),
    )
    # Platinum gets 25 + 5 reserved = 30
    assert platinum_result["available_inventory"] == 30
    # Standard gets 25 only
    assert standard_result["available_inventory"] == 25
    # Standard customer should see reserved stock flagged as a risk
    assert any(
        "reserved" in r.lower() for r in standard_result["risk_factors"]
    )


def test_competing_rush_orders_reduce_fulfillable():
    target = _today_plus(45)
    rush_orders = [
        {
            "order_id": "ORD-RUSH-1",
            "customer_id": "CUST-002",
            "sku": "ZP-7000",
            "quantity": 50,
            "status": "in_production",
            "priority": "rush",
        }
    ]
    slots = [{"date": _today_plus(10), "available_units": 60}]
    with_rush = compute_feasibility(
        inventory=INV_MEDIUM,
        production_slots=slots,
        orders=rush_orders,
        customer=CUST_STANDARD,
        quantity=70,
        target_date=target,
    )
    without_rush = compute_feasibility(
        inventory=INV_MEDIUM,
        production_slots=slots,
        orders=[],
        customer=CUST_STANDARD,
        quantity=70,
        target_date=target,
    )
    assert with_rush["total_fulfillable"] < without_rush["total_fulfillable"]
    assert any(
        "competing" in r.lower() for r in with_rush["risk_factors"]
    )


# ---- 5. Zero quantity edge case ---------------------------------------------


def test_zero_quantity_is_trivially_feasible():
    result = compute_feasibility(
        inventory=INV_TINY,
        production_slots=[],
        orders=[],
        customer=CUST_STANDARD,
        quantity=0,
        target_date=_today_plus(7),
    )
    assert result["feasibility_score"] == 1.0
    assert result["can_fulfill"] is True
    assert result["requested_quantity"] == 0
    assert result["days_late"] == 0


# ---- 6. Schema invariants ---------------------------------------------------


def test_result_contains_all_expected_keys():
    result = compute_feasibility(
        inventory=INV_AMPLE,
        production_slots=[],
        orders=[],
        customer=CUST_STANDARD,
        quantity=5,
        target_date=_today_plus(14),
    )
    expected = {
        "feasibility_score",
        "can_fulfill",
        "requested_quantity",
        "available_inventory",
        "production_capacity_by_date",
        "supplier_pipeline",
        "total_fulfillable",
        "earliest_promise_date",
        "requested_date",
        "days_late",
        "risk_factors",
        "recommendation_text",
    }
    assert expected.issubset(result.keys())
    assert isinstance(result["risk_factors"], list)
    assert isinstance(result["recommendation_text"], str)
    assert result["recommendation_text"]


def test_unknown_sku_yields_zero_inventory_and_risk():
    result = compute_feasibility(
        inventory={"found": False, "sku": "ZX-9999"},
        production_slots=[],
        orders=[],
        customer=CUST_STANDARD,
        quantity=5,
        target_date=_today_plus(14),
    )
    assert result["available_inventory"] == 0
    assert result["can_fulfill"] is False
    assert any("not found" in r.lower() for r in result["risk_factors"])
