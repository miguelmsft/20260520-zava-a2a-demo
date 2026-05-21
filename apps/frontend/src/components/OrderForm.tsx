/**
 * OrderForm — captures the order-feasibility query and submits a ChatRequest.
 *
 * SKU + customer dropdowns are seeded from static lists that mirror the
 * synthetic data in `apps/ops-agent/data/{inventory,customers}.json`.
 */

import { useState, type FormEvent } from "react";
import type { ChatRequest } from "../types";

const SKU_OPTIONS: { sku: string; name: string }[] = [
  { sku: "ZP-7000", name: "Industrial Centrifugal Pump" },
  { sku: "ZP-7100", name: "High-Pressure Diaphragm Pump" },
  { sku: "ZP-7200", name: "Variable-Speed Booster Pump" },
  { sku: "ZM-3200", name: "Servo Motor Assembly 2.5kW" },
  { sku: "ZM-3300", name: "BLDC Drive Motor 10kW" },
  { sku: "ZV-1500", name: "Stainless Steel Ball Valve 2in" },
  { sku: "ZS-0800", name: "Mechanical Seal Kit Type 21" },
];

const CUSTOMER_OPTIONS: { id: string; name: string }[] = [
  { id: "CUST-001", name: "Apex Hydraulics (Platinum)" },
  { id: "CUST-002", name: "Pacific Power Systems (Platinum)" },
  { id: "CUST-003", name: "MidWest Industrial Services (Gold)" },
  { id: "CUST-004", name: "Lonestar Refining Equipment (Gold)" },
  { id: "CUST-005", name: "Cascade Process Solutions (Gold)" },
  { id: "CUST-006", name: "Atlantic Marine Works (Silver)" },
];

function defaultTargetDate(): string {
  const d = new Date();
  d.setDate(d.getDate() + 60);
  return d.toISOString().slice(0, 10);
}

export interface OrderFormProps {
  isLoading: boolean;
  onSubmit: (req: ChatRequest) => void;
  onReset: () => void;
}

export function OrderForm({ isLoading, onSubmit, onReset }: OrderFormProps) {
  const [sku, setSku] = useState<string>(SKU_OPTIONS[0].sku);
  const [quantity, setQuantity] = useState<number>(50);
  const [targetDate, setTargetDate] = useState<string>(defaultTargetDate());
  const [customerId, setCustomerId] = useState<string>(CUSTOMER_OPTIONS[0].id);

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (isLoading) return;
    onSubmit({
      sku,
      quantity,
      target_date: targetDate,
      customer_id: customerId,
    });
  };

  const handleReset = () => {
    setSku(SKU_OPTIONS[0].sku);
    setQuantity(50);
    setTargetDate(defaultTargetDate());
    setCustomerId(CUSTOMER_OPTIONS[0].id);
    onReset();
  };

  return (
    <form className="order-form" onSubmit={handleSubmit}>
      <h2 className="order-form__title">Order Feasibility</h2>
      <p className="order-form__subtitle">
        Submit an order intent and watch the Foundry CS Agent collaborate with
        the LangGraph Ops Agent over A2A.
      </p>

      <label className="field">
        <span className="field__label">SKU</span>
        <select
          className="field__input"
          value={sku}
          onChange={(e) => setSku(e.target.value)}
          disabled={isLoading}
        >
          {SKU_OPTIONS.map((opt) => (
            <option key={opt.sku} value={opt.sku}>
              {opt.sku} — {opt.name}
            </option>
          ))}
        </select>
      </label>

      <label className="field">
        <span className="field__label">Quantity</span>
        <input
          type="number"
          className="field__input"
          min={1}
          max={1000}
          value={quantity}
          onChange={(e) => setQuantity(Math.max(1, Number(e.target.value) || 1))}
          disabled={isLoading}
          required
        />
      </label>

      <label className="field">
        <span className="field__label">Target date</span>
        <input
          type="date"
          className="field__input"
          value={targetDate}
          onChange={(e) => setTargetDate(e.target.value)}
          disabled={isLoading}
          required
        />
      </label>

      <label className="field">
        <span className="field__label">Customer</span>
        <select
          className="field__input"
          value={customerId}
          onChange={(e) => setCustomerId(e.target.value)}
          disabled={isLoading}
        >
          {CUSTOMER_OPTIONS.map((opt) => (
            <option key={opt.id} value={opt.id}>
              {opt.id} — {opt.name}
            </option>
          ))}
        </select>
      </label>

      <div className="order-form__actions">
        <button
          type="submit"
          className="btn btn--primary"
          disabled={isLoading}
        >
          {isLoading ? "Checking…" : "Check feasibility"}
        </button>
        <button
          type="button"
          className="btn btn--secondary"
          onClick={handleReset}
          disabled={isLoading}
        >
          Reset
        </button>
      </div>
    </form>
  );
}
