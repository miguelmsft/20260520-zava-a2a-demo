/**
 * Wire-format TypeScript types for the Zava frontend ⇄ backend contract.
 *
 * These mirror the Pydantic models in `apps/backend/app/models.py` and the
 * event taxonomy emitted by `apps/backend/app/agent_client.py`. Keep this
 * file in sync when the backend's `EventType` literal evolves.
 */

/** Inbound POST body for /api/chat. Mirrors `ChatRequest` in models.py. */
export interface ChatRequest {
  sku: string;
  quantity: number;
  /** ISO-8601 date, YYYY-MM-DD. */
  target_date: string;
  customer_id: string;
  /** Optional Foundry conversation id for multi-turn continuity. */
  conversation_id?: string;
}

/**
 * SSE event taxonomy emitted by the backend. The `data` payload shape is
 * loosely typed because Foundry Responses API events are dict-shaped.
 */
export type AgentEventType =
  | "status"
  | "text_delta"
  | "tool_call"
  | "a2a_hop"
  | "chart"
  | "done"
  | "error";

export interface AgentEvent<T = Record<string, unknown>> {
  type: AgentEventType;
  data: T;
}

// Convenience payload shapes (best-effort — backend uses free-form dicts).
export interface TextDeltaData {
  text: string;
}
export interface ToolCallData {
  tool: string;
  call_id?: string;
  status: "started" | "completed";
}
export interface A2AHopData {
  tool: string;
  call_id?: string;
  status: "started" | "completed";
  /**
   * Sub-kind of the A2A item. ``a2a_preview_call`` is the orchestrator's
   * outbound message to the worker; ``a2a_preview_call_output`` is the
   * worker's reply coming back inbound. Legacy preview SDK builds emit
   * ``remote_function_call`` for the input side.
   */
  kind?:
    | "a2a_preview_call"
    | "a2a_preview_call_output"
    | "remote_function_call"
    | string;
  /** "outbound" = orchestrator → worker; "inbound" = worker → orchestrator. */
  direction?: "outbound" | "inbound";
  /** Logical name of the peer agent (e.g. "LangGraph Ops Agent"). */
  peer_agent?: string;
  /** Coerced & redacted arguments dict/string the orchestrator sent. */
  arguments?: unknown;
  /** Coerced & redacted A2A worker reply (full dual-part artifact). */
  output?: unknown;
  /** Best-effort human-readable preview (TextPart or stringified args). */
  text_preview?: string | null;
  /** Best-effort structured preview (DataPart payload). */
  data_preview?: Record<string, unknown> | null;
}
export interface ChartData {
  mime_type?: string;
  file_id?: string;
  url?: string | null;
  data_b64?: string | null;
}
export interface StatusData {
  event?: string;
  item_type?: string;
}
export interface ErrorData {
  message: string;
}

/** Chat-panel message rendered in the UI. */
export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  text: string;
}

/** One entry rendered in the A2A activity timeline. */
export interface TimelineEntry {
  id: string;
  /** Logical agent that produced the entry. */
  agent: "Foundry CS Agent" | "LangGraph Ops Agent" | "System";
  /** Coarse kind for icon / styling decisions. */
  kind: "status" | "tool_call" | "a2a_hop" | "chart" | "done" | "error";
  label: string;
  status?: "started" | "completed" | "ok" | "failed";
  /** Epoch ms. */
  timestamp: number;
  /** Optional free-form details rendered under the row. */
  details?: string;
}

/** Resolved chart artifact ready for `<img>` rendering. */
export interface ChartArtifact {
  mimeType: string;
  /** Either a data URL or a remote URL. */
  src: string;
}

/**
 * One bubble in the Agent Conversation panel.
 *
 * The orchestrator (Foundry CS Agent) and worker (LangGraph Ops Agent) take
 * turns exchanging A2A messages. Each completed hop in the SSE stream
 * produces one `AgentMessage`:
 *
 *  - **outbound**: orchestrator → worker; `text` is the forwarded prompt.
 *  - **inbound**: worker → orchestrator; `text` is the TextPart preview and
 *    `data` is the structured DataPart payload (feasibility breakdown, etc).
 */
export interface AgentMessage {
  id: string;
  direction: "outbound" | "inbound";
  /** Sender display name (e.g. "Foundry CS Agent"). */
  sender: string;
  /** Receiver display name (e.g. "LangGraph Ops Agent"). */
  receiver: string;
  /** Primary human-readable content of the message. */
  text: string;
  /** Structured payload (DataPart). Only present on inbound replies. */
  data?: Record<string, unknown> | null;
  /** Full raw arguments or output for the "Show raw JSON" toggle. */
  raw?: unknown;
  /** Tool name from the SSE event (e.g. "a2a"). */
  tool?: string;
  timestamp: number;
}
