/**
 * ChatPanel — renders the user/assistant message thread.
 *
 * Auto-scrolls to the bottom whenever new content arrives. To stay
 * dependency-free, agent text is rendered as plain text with newline →
 * <br> conversion (no markdown library).
 */

import { useEffect, useRef, type ReactNode } from "react";
import type { ChatMessage, ChartArtifact } from "../types";
import { ChartDisplay } from "./ChartDisplay";

export interface ChatPanelProps {
  messages: ChatMessage[];
  chart: ChartArtifact | null;
  isLoading: boolean;
  error: string | null;
}

function renderText(text: string): ReactNode {
  if (!text) return null;
  // Split on newlines and interleave <br/> for readable plain rendering.
  const lines = text.split("\n");
  return lines.map((line, idx) => (
    <span key={idx}>
      {line}
      {idx < lines.length - 1 ? <br /> : null}
    </span>
  ));
}

export function ChatPanel({
  messages,
  chart,
  isLoading,
  error,
}: ChatPanelProps) {
  const scrollRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTop = el.scrollHeight;
  }, [messages, chart, isLoading, error]);

  return (
    <section className="chat-panel" aria-label="Conversation">
      <header className="chat-panel__header">
        <h2>Conversation</h2>
        {isLoading ? <span className="chip chip--live">streaming…</span> : null}
      </header>
      <div className="chat-panel__scroll" ref={scrollRef}>
        {messages.length === 0 ? (
          <div className="chat-panel__empty">
            Submit an order to start a conversation.
          </div>
        ) : null}
        {messages.map((m) => (
          <div
            key={m.id}
            className={`message message--${m.role}`}
            data-role={m.role}
          >
            <div className="message__role">
              {m.role === "user" ? "You" : "Foundry CS Agent"}
            </div>
            <div className="message__body">
              {m.text.length === 0 && m.role === "assistant" && isLoading ? (
                <span className="message__placeholder">…</span>
              ) : (
                renderText(m.text)
              )}
            </div>
          </div>
        ))}
        {chart ? (
          <div className="message message--assistant message--chart">
            <div className="message__role">Code Interpreter chart</div>
            <ChartDisplay chart={chart} />
          </div>
        ) : null}
        {error ? (
          <div className="message message--error" role="alert">
            <div className="message__role">Error</div>
            <div className="message__body">{error}</div>
          </div>
        ) : null}
      </div>
    </section>
  );
}
