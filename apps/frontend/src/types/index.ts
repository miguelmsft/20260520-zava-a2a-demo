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
  arguments?: unknown;
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
