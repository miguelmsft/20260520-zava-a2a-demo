/**
 * useChat — custom hook driving the Zava chat UI.
 *
 * Responsibilities:
 *  - POST a `ChatRequest` to /api/chat.
 *  - Read the response body as an SSE-framed stream using fetch +
 *    ReadableStream (NOT EventSource, which only supports GET).
 *  - Parse `data: {json}\n\n` frames into `AgentEvent`s.
 *  - Reduce events into UI state: messages[], timeline[], chartArtifact.
 *
 * The reducer is a pure function; consumers can unit-test it directly
 * via `chatReducer` below.
 */

import { useCallback, useReducer, useRef } from "react";
import type {
  AgentEvent,
  A2AHopData,
  ChartArtifact,
  ChartData,
  ChatMessage,
  ChatRequest,
  ErrorData,
  StatusData,
  TextDeltaData,
  TimelineEntry,
  ToolCallData,
} from "../types";

// ---------------------------------------------------------------------------
// Reducer state + actions
// ---------------------------------------------------------------------------

export interface ChatState {
  messages: ChatMessage[];
  timeline: TimelineEntry[];
  chart: ChartArtifact | null;
  isLoading: boolean;
  error: string | null;
  /** ID of the in-flight assistant message accumulating text deltas. */
  currentAssistantId: string | null;
}

export const initialChatState: ChatState = {
  messages: [],
  timeline: [],
  chart: null,
  isLoading: false,
  error: null,
  currentAssistantId: null,
};

export type ChatAction =
  | { type: "SEND"; userMessage: ChatMessage; assistantId: string }
  | { type: "EVENT"; event: AgentEvent }
  | { type: "STREAM_ERROR"; message: string }
  | { type: "STREAM_DONE" }
  | { type: "RESET" };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let _idCounter = 0;
function nextId(prefix: string): string {
  _idCounter += 1;
  return `${prefix}-${Date.now().toString(36)}-${_idCounter}`;
}

function appendTimeline(
  state: ChatState,
  entry: Omit<TimelineEntry, "id" | "timestamp"> & { timestamp?: number }
): TimelineEntry[] {
  return [
    ...state.timeline,
    {
      id: nextId("tl"),
      timestamp: entry.timestamp ?? Date.now(),
      ...entry,
    },
  ];
}

function appendAssistantText(
  messages: ChatMessage[],
  assistantId: string | null,
  delta: string
): ChatMessage[] {
  if (!assistantId) return messages;
  return messages.map((m) =>
    m.id === assistantId ? { ...m, text: m.text + delta } : m
  );
}

// ---------------------------------------------------------------------------
// Pure reducer (exported for unit testing)
// ---------------------------------------------------------------------------

export function chatReducer(state: ChatState, action: ChatAction): ChatState {
  switch (action.type) {
    case "SEND": {
      const assistantStub: ChatMessage = {
        id: action.assistantId,
        role: "assistant",
        text: "",
      };
      return {
        ...state,
        messages: [...state.messages, action.userMessage, assistantStub],
        timeline: [
          ...state.timeline,
          {
            id: nextId("tl"),
            agent: "System",
            kind: "status",
            label: "Request submitted",
            status: "started",
            timestamp: Date.now(),
          },
        ],
        chart: null,
        isLoading: true,
        error: null,
        currentAssistantId: action.assistantId,
      };
    }

    case "EVENT": {
      const { type, data } = action.event;
      switch (type) {
        case "text_delta": {
          const text = (data as unknown as TextDeltaData).text ?? "";
          if (!text) return state;
          return {
            ...state,
            messages: appendAssistantText(
              state.messages,
              state.currentAssistantId,
              text
            ),
          };
        }
        case "tool_call": {
          const d = data as unknown as ToolCallData;
          return {
            ...state,
            timeline: appendTimeline(state, {
              agent: "Foundry CS Agent",
              kind: "tool_call",
              label: `Tool: ${d.tool ?? "unknown"}`,
              status: d.status,
            }),
          };
        }
        case "a2a_hop": {
          const d = data as unknown as A2AHopData;
          return {
            ...state,
            timeline: appendTimeline(state, {
              agent: "LangGraph Ops Agent",
              kind: "a2a_hop",
              label: `A2A → ${d.tool ?? "ops-agent"}`,
              status: d.status,
              details:
                typeof d.arguments === "string"
                  ? d.arguments
                  : d.arguments
                  ? JSON.stringify(d.arguments)
                  : undefined,
            }),
          };
        }
        case "chart": {
          const d = data as unknown as ChartData;
          let chart: ChartArtifact | null = state.chart;
          if (d.data_b64) {
            chart = {
              mimeType: d.mime_type ?? "image/png",
              src: `data:${d.mime_type ?? "image/png"};base64,${d.data_b64}`,
            };
          } else if (d.url) {
            chart = { mimeType: d.mime_type ?? "image/png", src: d.url };
          }
          return {
            ...state,
            chart,
            timeline: appendTimeline(state, {
              agent: "Foundry CS Agent",
              kind: "chart",
              label: chart ? "Chart artifact received" : "Chart event (pending)",
              status: "completed",
            }),
          };
        }
        case "status": {
          const d = data as unknown as StatusData;
          return {
            ...state,
            timeline: appendTimeline(state, {
              agent: "Foundry CS Agent",
              kind: "status",
              label: d.event ?? "status",
              details: d.item_type,
            }),
          };
        }
        case "done": {
          return {
            ...state,
            timeline: appendTimeline(state, {
              agent: "System",
              kind: "done",
              label: "Stream completed",
              status: "ok",
            }),
            isLoading: false,
            currentAssistantId: null,
          };
        }
        case "error": {
          const d = data as unknown as ErrorData;
          return {
            ...state,
            error: d.message ?? "unknown error",
            timeline: appendTimeline(state, {
              agent: "System",
              kind: "error",
              label: "Error",
              status: "failed",
              details: d.message,
            }),
            isLoading: false,
            currentAssistantId: null,
          };
        }
        default:
          return state;
      }
    }

    case "STREAM_ERROR":
      return {
        ...state,
        error: action.message,
        isLoading: false,
        currentAssistantId: null,
        timeline: appendTimeline(state, {
          agent: "System",
          kind: "error",
          label: "Transport error",
          status: "failed",
          details: action.message,
        }),
      };

    case "STREAM_DONE":
      return { ...state, isLoading: false, currentAssistantId: null };

    case "RESET":
      return initialChatState;

    default:
      return state;
  }
}

// ---------------------------------------------------------------------------
// SSE frame parser
// ---------------------------------------------------------------------------

/**
 * Parse SSE buffer chunks into JSON `AgentEvent` payloads.
 *
 * Caller maintains the rolling buffer across chunks. Returns the events
 * extracted from the buffer plus the leftover (unterminated) tail.
 */
export function parseSseChunks(buffer: string): {
  events: AgentEvent[];
  rest: string;
} {
  const events: AgentEvent[] = [];
  let rest = buffer;

  // SSE frames are separated by a blank line (\n\n). Some servers use \r\n\r\n.
  // We normalize to \n only.
  const normalized = rest.replace(/\r\n/g, "\n");
  const parts = normalized.split("\n\n");
  // Last segment may be incomplete; keep it as the new buffer.
  rest = parts.pop() ?? "";

  for (const frame of parts) {
    const dataLines = frame
      .split("\n")
      .filter((l) => l.startsWith("data:"))
      .map((l) => l.slice(5).trimStart());
    if (dataLines.length === 0) continue;
    const payload = dataLines.join("\n");
    if (!payload) continue;
    try {
      const parsed = JSON.parse(payload) as AgentEvent;
      events.push(parsed);
    } catch {
      // Ignore malformed frames; backend should never emit them.
    }
  }

  return { events, rest };
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export interface UseChatResult extends ChatState {
  sendMessage: (req: ChatRequest) => Promise<void>;
  reset: () => void;
}

export function useChat(): UseChatResult {
  const [state, dispatch] = useReducer(chatReducer, initialChatState);
  const abortRef = useRef<AbortController | null>(null);

  const sendMessage = useCallback(async (req: ChatRequest) => {
    // Cancel any in-flight request first.
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const userMessage: ChatMessage = {
      id: nextId("u"),
      role: "user",
      text: `Check feasibility: ${req.quantity}× ${req.sku} for ${req.customer_id} by ${req.target_date}`,
    };
    const assistantId = nextId("a");
    dispatch({ type: "SEND", userMessage, assistantId });

    try {
      const resp = await fetch("/api/chat", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/event-stream",
        },
        body: JSON.stringify(req),
        signal: controller.signal,
      });

      if (!resp.ok || !resp.body) {
        const detail = resp.body ? await resp.text().catch(() => "") : "";
        dispatch({
          type: "STREAM_ERROR",
          message: `HTTP ${resp.status}${detail ? `: ${detail.slice(0, 200)}` : ""}`,
        });
        return;
      }

      const reader = resp.body.getReader();
      const decoder = new TextDecoder("utf-8");
      let buffer = "";

      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const { events, rest } = parseSseChunks(buffer);
        buffer = rest;
        for (const ev of events) {
          dispatch({ type: "EVENT", event: ev });
        }
      }
      // Flush any remaining buffered frame.
      if (buffer.trim().length > 0) {
        const { events } = parseSseChunks(buffer + "\n\n");
        for (const ev of events) dispatch({ type: "EVENT", event: ev });
      }
      dispatch({ type: "STREAM_DONE" });
    } catch (err) {
      if ((err as { name?: string }).name === "AbortError") return;
      dispatch({
        type: "STREAM_ERROR",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }, []);

  const reset = useCallback(() => {
    abortRef.current?.abort();
    dispatch({ type: "RESET" });
  }, []);

  return { ...state, sendMessage, reset };
}
