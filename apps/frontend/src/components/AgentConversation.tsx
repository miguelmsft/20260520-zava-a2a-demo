/**
 * AgentConversation — chat-style transcript of A2A messages.
 *
 * Renders one bubble per completed A2A hop so a viewer can literally watch
 * the Foundry CS Agent (orchestrator) and the LangGraph Ops Agent (worker)
 * "talking" to each other:
 *
 *  - **outbound** bubbles (orchestrator → worker) are aligned left and use
 *    the primary brand color.
 *  - **inbound** bubbles (worker → orchestrator) are aligned right and use
 *    the A2A accent color.
 *
 * For inbound replies that carry a DataPart payload, the top-level
 * feasibility fields render as labeled rows (option 3c from the planning
 * doc). The full raw JSON is collapsible via a per-bubble toggle.
 *
 * Empty-state: when the orchestrator transient-bypasses A2A and replies
 * directly (a known GA quirk, ~1 in 3 runs), we surface a clear hint so
 * the user understands why no bubbles appear.
 */

import { useState } from "react";
import type { AgentMessage } from "../types";

export interface AgentConversationProps {
  messages: AgentMessage[];
  isLoading: boolean;
}

/** Keys we'd like to surface as their own labeled row in inbound bubbles. */
const FEATURED_DATA_KEYS: ReadonlyArray<string> = [
  "feasibility_score",
  "can_fulfill",
  "total_fulfillable",
  "requested_quantity",
  "earliest_promise_date",
  "requested_date",
  "days_late",
  "available_inventory",
  "recommendation_text",
];

function formatValue(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") {
    // Render small floats with 2 decimals; integers unchanged.
    return Number.isInteger(value) ? String(value) : value.toFixed(2);
  }
  if (typeof value === "boolean") return value ? "✓ yes" : "✗ no";
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function humanizeKey(key: string): string {
  return key
    .replace(/[_-]/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function Bubble({ message }: { message: AgentMessage }) {
  const [showRaw, setShowRaw] = useState(false);
  const isInbound = message.direction === "inbound";

  // Pull featured fields (in declared order) plus any remaining keys for
  // the inbound DataPart. Outbound bubbles only render the text body.
  const data = message.data ?? null;
  const featured: Array<[string, unknown]> = [];
  const remaining: Array<[string, unknown]> = [];
  if (data) {
    const seen = new Set<string>();
    for (const key of FEATURED_DATA_KEYS) {
      if (Object.prototype.hasOwnProperty.call(data, key)) {
        featured.push([key, (data as Record<string, unknown>)[key]]);
        seen.add(key);
      }
    }
    for (const [key, value] of Object.entries(data)) {
      if (!seen.has(key)) remaining.push([key, value]);
    }
  }

  const timestamp = new Date(message.timestamp).toLocaleTimeString();
  const rawJson = (() => {
    try {
      return JSON.stringify(message.raw ?? {}, null, 2);
    } catch {
      return String(message.raw ?? "");
    }
  })();

  return (
    <div
      className={`bubble bubble--${isInbound ? "inbound" : "outbound"}`}
      data-testid={`agent-bubble-${message.direction}`}
    >
      <div className="bubble__header">
        <span className="bubble__sender">{message.sender}</span>
        <span className="bubble__arrow">{isInbound ? "←" : "→"}</span>
        <span className="bubble__receiver">{message.receiver}</span>
        <span className="bubble__time">{timestamp}</span>
      </div>

      {message.text ? (
        <p className="bubble__text">{message.text}</p>
      ) : (
        <p className="bubble__text bubble__text--muted">
          (no text content)
        </p>
      )}

      {featured.length > 0 && (
        <dl className="bubble__data">
          {featured.map(([key, value]) => (
            <div className="bubble__data-row" key={key}>
              <dt>{humanizeKey(key)}</dt>
              <dd>{formatValue(value)}</dd>
            </div>
          ))}
          {remaining.length > 0 && (
            <div className="bubble__data-row bubble__data-row--more">
              <dt>{remaining.length} more field(s)</dt>
              <dd>—</dd>
            </div>
          )}
        </dl>
      )}

      {message.raw !== undefined && message.raw !== null && (
        <details
          className="bubble__raw"
          open={showRaw}
          onToggle={(e) => setShowRaw((e.target as HTMLDetailsElement).open)}
        >
          <summary>{showRaw ? "▾ Hide raw JSON" : "▸ Show raw JSON"}</summary>
          <pre className="bubble__raw-pre">{rawJson}</pre>
        </details>
      )}
    </div>
  );
}

export function AgentConversation({
  messages,
  isLoading,
}: AgentConversationProps) {
  return (
    <section
      className="conversation"
      aria-labelledby="agent-conversation-heading"
    >
      <header className="conversation__header">
        <h2 id="agent-conversation-heading" className="conversation__title">
          Agent Conversation
        </h2>
        <p className="conversation__subtitle">
          Live A2A messages exchanged between the Foundry orchestrator and
          the LangGraph worker.
        </p>
      </header>

      <div className="conversation__list">
        {messages.length === 0 && !isLoading && (
          <div className="conversation__empty" data-testid="conversation-empty">
            <p>No A2A messages yet.</p>
            <p className="conversation__empty-hint">
              Submit an order to see the orchestrator delegate to the
              LangGraph Ops Agent. If the orchestrator responds without
              delegating (a known transient Foundry GA behavior), no
              bubbles will appear — resubmit to see the agent-to-agent flow.
            </p>
          </div>
        )}

        {messages.length === 0 && isLoading && (
          <div className="conversation__empty" data-testid="conversation-loading">
            <p>Waiting for the orchestrator to delegate…</p>
          </div>
        )}

        {messages.map((m) => (
          <Bubble key={m.id} message={m} />
        ))}
      </div>
    </section>
  );
}
