"""Unit tests for the ``app.artifacts`` allowlist."""

from __future__ import annotations

import os
import time

os.environ.setdefault("DEV_MODE", "true")

import pytest  # noqa: E402

from app.artifacts import ArtifactAllowlist  # noqa: E402


def test_is_valid_id_accepts_proper_prefixes() -> None:
    assert ArtifactAllowlist.is_valid_id("cntr_abc123", "cfile_def456")


@pytest.mark.parametrize(
    "container_id,file_id",
    [
        ("../etc/passwd", "cfile_def"),
        ("cntr_abc", "../../secret.png"),
        ("notacntr", "cfile_def"),
        ("cntr_abc", "notacfile"),
        ("cntr_with space", "cfile_x"),
        ("", "cfile_def"),
        ("cntr_abc", ""),
    ],
)
def test_is_valid_id_rejects_malformed(container_id: str, file_id: str) -> None:
    assert not ArtifactAllowlist.is_valid_id(container_id, file_id)


def test_register_and_is_allowed_roundtrip() -> None:
    a = ArtifactAllowlist(ttl_seconds=60)
    assert a.register("cntr_abc", "cfile_def") is True
    assert a.is_allowed("cntr_abc", "cfile_def") is True
    # Unregistered pair must be rejected even when the IDs are well-formed.
    assert a.is_allowed("cntr_zzz", "cfile_yyy") is False


def test_register_rejects_malformed_ids() -> None:
    a = ArtifactAllowlist()
    assert a.register("not-a-container", "cfile_def") is False
    assert not a.is_allowed("not-a-container", "cfile_def")


def test_ttl_expiration() -> None:
    # 0-second TTL → entries should already be stale on the next tick.
    a = ArtifactAllowlist(ttl_seconds=0)
    a.register("cntr_abc", "cfile_def")
    time.sleep(0.01)
    assert a.is_allowed("cntr_abc", "cfile_def") is False


def test_max_entries_evicts_oldest() -> None:
    a = ArtifactAllowlist(max_entries=2)
    a.register("cntr_a", "cfile_1")
    a.register("cntr_b", "cfile_2")
    a.register("cntr_c", "cfile_3")
    # Either the first or second is evicted (oldest by expiry time);
    # the third must still be present.
    allowed_count = sum(
        a.is_allowed(c, f)
        for c, f in [("cntr_a", "cfile_1"), ("cntr_b", "cfile_2"), ("cntr_c", "cfile_3")]
    )
    assert allowed_count == 2
    assert a.is_allowed("cntr_c", "cfile_3")
