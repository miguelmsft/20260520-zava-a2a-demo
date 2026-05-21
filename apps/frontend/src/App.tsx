/**
 * App — three-pane layout for the Zava Smart Order Feasibility demo.
 *
 *   ┌──────────────┬───────────────────────────────┐
 *   │              │  Chat panel (top)             │
 *   │ Order form   │                               │
 *   │ (sidebar)    ├───────────────────────────────┤
 *   │              │  A2A activity timeline        │
 *   └──────────────┴───────────────────────────────┘
 */

import { OrderForm } from "./components/OrderForm";
import { ChatPanel } from "./components/ChatPanel";
import { A2ATimeline } from "./components/A2ATimeline";
import { useChat } from "./hooks/useChat";

export function App() {
  const {
    messages,
    timeline,
    chart,
    isLoading,
    error,
    sendMessage,
    reset,
  } = useChat();

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
            <A2ATimeline entries={timeline} />
          </div>
        </main>
      </div>

      <footer className="app__footer">
        Demo build · public endpoints · streaming via SSE over <code>/api/chat</code>
      </footer>
    </div>
  );
}
