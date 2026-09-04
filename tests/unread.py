#!/usr/bin/env python3
"""Prove unread bubbles fire from last-roster the way Grok Bot does."""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEY = "sand.client.slice.account.test.roster.last-roster"


def blob_name(key: str) -> str:
    raw = base64.b32encode(key.encode("ascii")).decode("ascii").rstrip("=").lower()
    return raw + ".blob"


def run_inbox(persist: Path) -> dict:
    env = os.environ.copy()
    env["GROKBOT_PERSIST"] = str(persist)
    out = subprocess.check_output(["python3", str(ROOT / "inbox.py")], env=env)
    return json.loads(out)


def write_roster(persist: Path, rows: list) -> None:
    persist.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": 3,
        "value": {"rows": rows},
        "ok": True,
    }
    (persist / blob_name(KEY)).write_text(json.dumps(payload), encoding="utf-8")


def row(name: str, **extra) -> dict:
    base = {
        "id": extra.pop("id", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        "name": name,
        "description": "",
        "title": "",
        "avatarShape": "wedge",
        "avatarColor": "red",
        "hasUnread": False,
        "unreadCount": 0,
        "lastActivityAt": 1000,
        "lastViewedAt": 1000,
        "awaitingUserResponse": None,
        "isHiddenFromSidebar": False,
        "lastEntry": {"kind": "text", "text": "hello from the bot"},
    }
    base.update(extra)
    return base


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="grok-bots-unread-") as tmp:
        persist = Path(tmp)
        write_roster(
            persist,
            [
                row("Counted", id="11111111-1111-1111-1111-111111111111", hasUnread=True, unreadCount=3),
                row("Flagged", id="22222222-2222-2222-2222-222222222222", hasUnread=True, unreadCount=0),
                row("Newer", id="33333333-3333-3333-3333-333333333333", lastActivityAt=5000, lastViewedAt=1000),
                row("Read", id="44444444-4444-4444-4444-444444444444", hasUnread=False, unreadCount=0, lastActivityAt=1000, lastViewedAt=2000),
            ],
        )
        data = run_inbox(persist)
        assert data["ok"] is True, data
        by = {b["name"]: b["unread"] for b in data["bots"]}
        assert by["Counted"] == 3, by
        assert by["Flagged"] == 1, by
        assert by["Newer"] == 1, by
        assert by["Read"] == 0, by
        total = sum(by.values())
        assert total == 5, total
        print("unread bubbles ok · Counted=3 Flagged=1 Newer=1 Read=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
