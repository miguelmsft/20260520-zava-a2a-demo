"""In-memory allowlist of Foundry container files observed during chat streams.

Why this exists
---------------
The Foundry Responses API exposes Code Interpreter outputs (charts, etc.) as
files inside an ephemeral *container* (``cntr_…``) keyed by ``file_id``
(``cfile_…``). The IDs travel down our SSE channel as part of
``response.output_text.annotation.added`` events so that the React frontend
can render the chart.

To actually display the image in the browser we expose
``GET /api/files/{container_id}/{file_id}`` which proxies the bytes from
Foundry using the backend's managed-identity credential. That makes the
backend a **confused-deputy** target: any caller who knows or guesses a valid
``container_id`` / ``file_id`` could trick us into downloading and serving
arbitrary tenant files.

This module mitigates that by maintaining a short-lived allowlist of pairs
that we ourselves emitted on a chat stream. Only allowlisted pairs may be
served, with a TTL (default 1 hour) and bounded size.

Trade-offs (intentional for a demo):

* Process-local, in-memory state — survives only as long as the FastAPI
  process. Restarting the backend invalidates pending image URLs.
* No per-user scoping — the demo is a single-tenant local backend. Multi-
  tenant deployments would key the allowlist by session/auth identity.
"""

from __future__ import annotations

import re
import threading
import time
from dataclasses import dataclass

# Regexes are intentionally strict to avoid path-traversal / weird IDs.
# Foundry IDs are hexadecimal suffixes after a known prefix.
_CONTAINER_RE = re.compile(r"^cntr_[A-Za-z0-9]+$")
_FILE_RE = re.compile(r"^cfile_[A-Za-z0-9]+$")

DEFAULT_TTL_SECONDS = 60 * 60  # 1 hour
MAX_ENTRIES = 1024  # bound memory if the demo runs for hours


@dataclass(frozen=True)
class ArtifactKey:
    container_id: str
    file_id: str


class ArtifactAllowlist:
    """Thread-safe allowlist with TTL eviction."""

    def __init__(self, ttl_seconds: int = DEFAULT_TTL_SECONDS, max_entries: int = MAX_ENTRIES) -> None:
        self._ttl = ttl_seconds
        self._max = max_entries
        self._lock = threading.Lock()
        self._entries: dict[ArtifactKey, float] = {}

    @staticmethod
    def is_valid_id(container_id: str, file_id: str) -> bool:
        """Return True iff both IDs match the strict Foundry format."""
        return bool(_CONTAINER_RE.match(container_id) and _FILE_RE.match(file_id))

    def register(self, container_id: str, file_id: str) -> bool:
        """Record an observed (container_id, file_id) pair.

        Returns True if the IDs are well-formed and got registered. The
        backend should refuse to emit a chart event when this returns False
        because the file endpoint will reject it later anyway.
        """
        if not self.is_valid_id(container_id, file_id):
            return False
        now = time.monotonic()
        with self._lock:
            self._evict_expired(now)
            if len(self._entries) >= self._max:
                # Drop the oldest to keep the dict bounded.
                oldest_key = min(self._entries, key=lambda k: self._entries[k])
                self._entries.pop(oldest_key, None)
            self._entries[ArtifactKey(container_id, file_id)] = now + self._ttl
        return True

    def is_allowed(self, container_id: str, file_id: str) -> bool:
        """Return True iff this pair was previously :meth:`register`-ed and
        has not yet expired."""
        if not self.is_valid_id(container_id, file_id):
            return False
        key = ArtifactKey(container_id, file_id)
        now = time.monotonic()
        with self._lock:
            expires_at = self._entries.get(key)
            if expires_at is None:
                return False
            if expires_at < now:
                self._entries.pop(key, None)
                return False
            return True

    def _evict_expired(self, now: float) -> None:
        # Called with ``self._lock`` held.
        stale = [k for k, exp in self._entries.items() if exp < now]
        for k in stale:
            self._entries.pop(k, None)

    def clear(self) -> None:
        """Test-only: wipe state between cases."""
        with self._lock:
            self._entries.clear()


# Module-level singleton consumed by both ``agent_client`` (writer) and
# ``main`` (reader).
artifact_allowlist = ArtifactAllowlist()
