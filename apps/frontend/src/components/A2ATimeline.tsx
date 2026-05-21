/**
 * A2ATimeline — vertical activity feed of agent events.
 *
 * Each row shows an icon, the originating agent, a label, an optional
 * status badge, and a timestamp. A2A hops use a distinct accent color so
 * cross-agent traffic stands out for the demo audience.
 */

import type { TimelineEntry } from "../types";

export interface A2ATimelineProps {
  entries: TimelineEntry[];
}

const KIND_ICON: Record<TimelineEntry["kind"], string> = {
  status: "•",
  tool_call: "🛠",
  a2a_hop: "↔",
  chart: "📊",
  done: "✓",
  error: "⚠",
};

function formatTime(ts: number): string {
  const d = new Date(ts);
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  const ss = String(d.getSeconds()).padStart(2, "0");
  return `${hh}:${mm}:${ss}`;
}

export function A2ATimeline({ entries }: A2ATimelineProps) {
  return (
    <section className="timeline" aria-label="A2A activity timeline">
      <header className="timeline__header">
        <h2>A2A Activity Timeline</h2>
        <span className="timeline__count">{entries.length} events</span>
      </header>
      {entries.length === 0 ? (
        <div className="timeline__empty">
          No activity yet. Submit an order to see Foundry → A2A → LangGraph hops.
        </div>
      ) : (
        <ol className="timeline__list">
          {entries.map((e) => (
            <li
              key={e.id}
              className={`timeline__item timeline__item--${e.kind}`}
              data-agent={e.agent}
            >
              <span className="timeline__icon" aria-hidden="true">
                {KIND_ICON[e.kind]}
              </span>
              <div className="timeline__body">
                <div className="timeline__row1">
                  <span className="timeline__agent">{e.agent}</span>
                  <span className="timeline__label">{e.label}</span>
                  {e.status ? (
                    <span
                      className={`badge badge--${e.status}`}
                      aria-label={`status: ${e.status}`}
                    >
                      {e.status}
                    </span>
                  ) : null}
                </div>
                {e.details ? (
                  <div className="timeline__details">{e.details}</div>
                ) : null}
              </div>
              <time className="timeline__time" dateTime={new Date(e.timestamp).toISOString()}>
                {formatTime(e.timestamp)}
              </time>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
