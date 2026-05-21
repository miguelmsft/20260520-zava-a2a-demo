/**
 * App — three-pane layout for the Zava Smart Order Feasibility demo.
 *
 *   ┌──────────────┬───────────────────────────────┐
 *   │              │  Chat panel (top)             │
 *   │ Order form   │                               │
 *   │ (sidebar)    ├───────────────────────────────┤
 *   │              │  Tabbed view (bottom):        │
 *   │              │  • Agent Conversation (def.)  │
 *   │              │  • Activity Timeline          │
 *   └──────────────┴───────────────────────────────┘
 */

import { useState } from "react";
import { OrderForm } from "./components/OrderForm";
import { ChatPanel } from "./components/ChatPanel";
import { A2ATimeline } from "./components/A2ATimeline";
import { AgentConversation } from "./components/AgentConversation";
import { useChat } from "./hooks/useChat";

type BottomTab = "conversation" | "timeline";

export function App() {
  const {
    messages,
    timeline,
    agentMessages,
    chart,
    isLoading,
    error,
    sendMessage,
    reset,
  } = useChat();

  const [bottomTab, setBottomTab] = useState<BottomTab>("conversation");

  return (
    <div className="app">
      <header className="app__header">
        <div className="app__brand">
          <span className="app__brand-mark">Zava</span>
          <span className="app__brand-sub">Smart Order Feasibility</span>
        </div>
        <div className="app__tag">
          Foundry CS Agent <span className="app__arrow">↔ A2A ↔</span>{" "}
          LangGraph Ops Agent
        </div>
      </header>

      <div className="app__layout">
        <aside className="app__sidebar">
          <OrderForm
            isLoading={isLoading}
            onSubmit={sendMessage}
            onReset={reset}
          />
        </aside>

        <main className="app__main">
          <div className="app__main-top">
            <ChatPanel
              messages={messages}
              chart={chart}
              isLoading={isLoading}
              error={error}
            />
          </div>
          <div className="app__main-bottom">
            <div
              className="tabs"
              role="tablist"
              aria-label="Bottom pane view"
            >
              <button
                type="button"
                role="tab"
                aria-selected={bottomTab === "conversation"}
                className={`tab ${bottomTab === "conversation" ? "tab--active" : ""}`}
                onClick={() => setBottomTab("conversation")}
                data-testid="tab-conversation"
              >
                Agent Conversation
                {agentMessages.length > 0 && (
                  <span className="tab__badge">{agentMessages.length}</span>
                )}
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={bottomTab === "timeline"}
                className={`tab ${bottomTab === "timeline" ? "tab--active" : ""}`}
                onClick={() => setBottomTab("timeline")}
                data-testid="tab-timeline"
              >
                Activity Timeline
                {timeline.length > 0 && (
                  <span className="tab__badge">{timeline.length}</span>
                )}
              </button>
            </div>
            <div className="tab-panel" role="tabpanel">
              {bottomTab === "conversation" ? (
                <AgentConversation
                  messages={agentMessages}
                  isLoading={isLoading}
                />
              ) : (
                <A2ATimeline entries={timeline} />
              )}
            </div>
          </div>
        </main>
      </div>

      <footer className="app__footer">
        Demo build · public endpoints · streaming via SSE over <code>/api/chat</code>
      </footer>
    </div>
  );
}
