"""Pure feasibility-computation logic for Zava order requests.

The single public function `compute_feasibility` is deliberately stateless
so it can be unit-tested without any LLM, file IO, or network calls.

Inputs are typed as plain dicts/lists matching the shapes returned by the
LangChain tools in `app.tools` (see also plan §A.4 / §A.5).
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

# Customers in these tiers cause inventory `reserved` to be honored as
# "set aside for higher-priority orders" — a request from a customer at
# or above this tier may draw from `reserved`; below it may not.
_TIER_RANK = {"standard": 0, "silver": 1, "gold": 2, "platinum": 3}
_PRIORITY_RESERVED_THRESHOLD = "gold"  # platinum/gold can use reserved stock


def _parse_date(s: str) -> date:
    return datetime.strptime(s, "%Y-%m-%d").date()


def _fmt_date(d: date) -> str:
    return d.strftime("%Y-%m-%d")


def _customer_can_use_reserved(customer: dict[str, Any]) -> bool:
    tier = (customer or {}).get("priority_tier", "standard")
    return _TIER_RANK.get(tier, 0) >= _TIER_RANK[_PRIORITY_RESERVED_THRESHOLD]


def _competing_higher_priority_demand(
    orders: list[dict[str, Any]],
    customer: dict[str, Any],
) -> int:
    """Sum of quantities for competing OPEN orders that outrank the
    current customer's tier — these eat into available production capacity
    and cannot be displaced.
    """
    if not orders:
        return 0
    my_tier = _TIER_RANK.get((customer or {}).get("priority_tier", "standard"), 0)
    open_states = {"confirmed", "in_production"}
    total = 0
    for o in orders:
        if o.get("status") not in open_states:
            continue
        # Rush priority is treated as one tier higher than the customer's
        # nominal tier when ranking competing demand.
        order_priority_bonus = 1 if o.get("priority") == "rush" else 0
        # Without per-customer-tier resolution, treat all listed open
        # orders as same-tier demand and let `priority=rush` push them
        # above us. Conservative.
        if order_priority_bonus > 0 and order_priority_bonus > 0 - my_tier:
            total += int(o.get("quantity", 0))
    return total


def compute_feasibility(
    inventory: dict[str, Any],
    production_slots: list[dict[str, Any]],
    orders: list[dict[str, Any]],
    customer: dict[str, Any],
    quantity: int,
    target_date: str,
) -> dict[str, Any]:
    """Compute order feasibility for a Zava SKU.

    Args:
        inventory: Inventory record dict as returned by `lookup_inventory`.
            Must contain `available`, `reserved`, `supplier_lead_time_days`
            when `found` is true. Pass `{"found": False, ...}` for unknown SKU.
        production_slots: Flat list of slot dicts ``{"date","available_units"}``
            — typically derived from the per-machine slot lists returned by
            `lookup_production_schedule`. Slots strictly before `target_date`
            are summed into `production_capacity_by_date`.
        orders: List of competing open orders for the same SKU (from
            `lookup_order_book`).
        customer: Customer record dict (from `lookup_customer`); empty dict
            if no customer context is available.
        quantity: Requested quantity. Must be non-negative.
        target_date: Requested ship date, ``YYYY-MM-DD``.

    Returns:
        A dict with the schema documented in plan §A.5:
            feasibility_score, can_fulfill, requested_quantity,
            available_inventory, production_capacity_by_date,
            supplier_pipeline, total_fulfillable, earliest_promise_date,
            requested_date, days_late, risk_factors, recommendation_text.
    """
    requested_qty = int(quantity)
    if requested_qty < 0:
        raise ValueError("quantity must be non-negative")

    target = _parse_date(target_date)
    today = date.today()
    risk_factors: list[str] = []

    # ---- 1. Available inventory --------------------------------------------------
    if inventory and inventory.get("found"):
        available = int(inventory.get("available", 0))
        reserved = int(inventory.get("reserved", 0))
        supplier_lead_time = int(inventory.get("supplier_lead_time_days", 0))
        if _customer_can_use_reserved(customer):
            available_inventory = available + reserved
        else:
            available_inventory = available
            if reserved > 0:
                risk_factors.append(
                    f"{reserved} units reserved for higher-tier customers — "
                    "not drawable for this request"
                )
    else:
        available_inventory = 0
        supplier_lead_time = 0
        risk_factors.append("SKU not found in inventory database")

    # ---- 2. Production capacity by target_date ----------------------------------
    production_capacity = 0
    earliest_production_date: date | None = None
    cumulative = 0
    needed_after_inventory = max(requested_qty - available_inventory, 0)
    sorted_slots = sorted(
        (s for s in (production_slots or []) if s.get("date")),
        key=lambda s: s["date"],
    )
    for slot in sorted_slots:
        try:
            slot_date = _parse_date(slot["date"])
        except ValueError:
            continue
        units = int(slot.get("available_units", 0))
        if slot_date <= target:
            production_capacity += units
        # Track when cumulative production first covers the shortfall.
        if earliest_production_date is None and units > 0:
            cumulative += units
            if cumulative >= needed_after_inventory:
                earliest_production_date = slot_date
        elif earliest_production_date is None:
            cumulative += units

    if needed_after_inventory == 0:
        # Inventory already covers the request — earliest promise is today.
        earliest_production_date = today

    # ---- 3. Supplier pipeline (only counted if it can land by target_date) ------
    supplier_pipeline = 0
    if supplier_lead_time > 0:
        supplier_arrival = today + timedelta(days=supplier_lead_time)
        if supplier_arrival <= target:
            # Use available inventory level as a proxy for incoming pipeline
            # (the synthetic dataset has no separate PO field). This is a
            # conservative model: treat supplier pipeline as one full
            # restock = available level.
            supplier_pipeline = int(inventory.get("available", 0)) if inventory else 0
        else:
            risk_factors.append(
                f"Supplier lead time {supplier_lead_time} days exceeds window "
                f"to {target_date} — pipeline not counted"
            )

    # ---- 4. Higher-priority competing demand ------------------------------------
    competing_demand = _competing_higher_priority_demand(orders, customer)
    if competing_demand > 0:
        risk_factors.append(
            f"{competing_demand} units of higher-priority competing demand "
            f"in the order book"
        )

    # ---- 5. Aggregate -----------------------------------------------------------
    total_fulfillable = max(
        available_inventory
        + production_capacity
        + supplier_pipeline
        - competing_demand,
        0,
    )

    if requested_qty == 0:
        feasibility_score = 1.0
        can_fulfill = True
    else:
        feasibility_score = min(total_fulfillable / requested_qty, 1.0)
        can_fulfill = total_fulfillable >= requested_qty

    # ---- 6. Earliest promise date ----------------------------------------------
    if requested_qty == 0:
        earliest_promise_date = today
    elif available_inventory >= requested_qty:
        earliest_promise_date = today
    elif earliest_production_date is not None:
        earliest_promise_date = earliest_production_date
    elif supplier_pipeline > 0 and supplier_lead_time > 0:
        earliest_promise_date = today + timedelta(days=supplier_lead_time)
    else:
        # Fall back to last known production slot date if any
        if sorted_slots:
            try:
                earliest_promise_date = _parse_date(sorted_slots[-1]["date"])
            except ValueError:
                earliest_promise_date = target
        else:
            earliest_promise_date = target

    days_late = max((earliest_promise_date - target).days, 0)

    # ---- 7. Additional risk factors --------------------------------------------
    if (
        inventory
        and inventory.get("found")
        and inventory.get("on_hand", 0)
        and int(inventory.get("on_hand", 0)) <= int(inventory.get("reorder_point", 0))
    ):
        risk_factors.append(
            "Inventory at or below reorder point — replenishment recommended"
        )
    # Surface high-load machines
    # (we can't see per-machine load from the flat slot list, so this is
    # best-effort and only added if the caller stuffs `_machines` into the
    # first slot — kept out for now.)

    # ---- 8. Recommendation text -------------------------------------------------
    customer_name = (customer or {}).get("name") or (customer or {}).get(
        "customer_id"
    ) or "the customer"
    tier = (customer or {}).get("priority_tier", "standard")
    sku = (inventory or {}).get("sku", "the requested SKU")

    if requested_qty == 0:
        recommendation_text = (
            f"Zero-quantity request for {sku} — trivially feasible."
        )
    elif can_fulfill and days_late == 0:
        recommendation_text = (
            f"Order is fully feasible by {target_date}. "
            f"{customer_name} ({tier} tier) — recommend confirming the ship date."
        )
    elif can_fulfill and days_late > 0:
        recommendation_text = (
            f"Order is feasible with a {days_late}-day delay "
            f"(promise {_fmt_date(earliest_promise_date)} vs requested {target_date}). "
            f"Recommend confirming the revised ship date with {customer_name}."
        )
    else:
        shortfall = requested_qty - total_fulfillable
        recommendation_text = (
            f"Order is NOT fully feasible: short by {shortfall} units "
            f"(score {feasibility_score:.2f}). "
            f"Earliest partial promise {_fmt_date(earliest_promise_date)}. "
            f"Recommend negotiating split shipment or extended timeline with "
            f"{customer_name}."
        )

    return {
        "feasibility_score": round(feasibility_score, 4),
        "can_fulfill": bool(can_fulfill),
        "requested_quantity": requested_qty,
        "available_inventory": int(available_inventory),
        "production_capacity_by_date": int(production_capacity),
        "supplier_pipeline": int(supplier_pipeline),
        "total_fulfillable": int(total_fulfillable),
        "earliest_promise_date": _fmt_date(earliest_promise_date),
        "requested_date": target_date,
        "days_late": int(days_late),
        "risk_factors": risk_factors,
        "recommendation_text": recommendation_text,
    }
