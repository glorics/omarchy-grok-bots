#!/usr/bin/env python3
"""Message path: last-line preview, waiting, unread, clip, skip stubs, no transcripts."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from unread import ROOT, KEY, blob_name, run_inbox, write_roster, row


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="grok-bots-messages-") as tmp:
        persist = Path(tmp)
        long_text = "A" * 400
        write_roster(
            persist,
            [
                row(
                    "Angela",
                    id="284a1d46-bc72-49fb-9c3b-c14f8b5bef80",
                    avatarShape="tablet",
                    avatarColor="red",
                    lastEntry={"kind": "text", "text": "LinkedIn s'ouvre. Vérifie Cloudflare."},
                    title="Dentalog AI LinkedIn",
                ),
                row(
                    "Laszlo",
                    id="b5bcec11-92ba-4bff-9e45-ef2650ee259f",
                    avatarShape=None,
                    avatarColor=None,
                    lastEntry={"kind": "text", "text": "La veille reste en pause."},
                ),
                row(
                    "New Bot",
                    id="c7dd7de4-cbc5-4498-8caf-065b10304ed9",
                    avatarShape=None,
                    avatarColor=None,
                    awaitingUserResponse=True,
                    lastEntry={
                        "kind": "text",
                        "text": "What should I help with first?",
                        "sessionPreview": {
                            "kind": "widget_options",
                            "prompt": "What should I help with first?",
                            "options": ["Coding / projects", "Writing / research"],
                        },
                    },
                ),
                row(
                    "Clipped",
                    id="55555555-5555-5555-5555-555555555555",
                    lastEntry={"kind": "text", "text": long_text},
                ),
                row(
                    "Hidden",
                    id="66666666-6666-6666-6666-666666666666",
                    isHiddenFromSidebar=True,
                    lastEntry={"kind": "text", "text": "should not appear"},
                ),
                row(
                    "New Bot",
                    id="77777777-7777-7777-7777-777777777777",
                    lastEntry=None,
                    description="",
                ),
            ],
        )
        # A transcript blob must be ignored (size would fail if opened as roster).
        (persist / blob_name(KEY.replace("last-roster", "transcript.replicas.dead"))).write_bytes(b"x" * 80_000)

        data = run_inbox(persist)
        assert data["ok"] is True, data
        names = [b["name"] for b in data["bots"]]
        assert "Hidden" not in names, names
        assert names.count("New Bot") == 1, names
        by = {b["name"]: b for b in data["bots"]}

        assert by["Angela"]["preview"] == "LinkedIn s'ouvre. Vérifie Cloudflare."
        assert by["Angela"]["team"] == "Dentalog AI LinkedIn"
        assert by["Angela"]["shape"] == "tablet"
        assert by["Angela"]["color"].upper() == "#FF263C"

        assert by["Laszlo"]["preview"] == "La veille reste en pause."
        assert by["Laszlo"]["shape"] == "wedge"
        assert by["Laszlo"]["color"].upper() == "#FF263C"

        assert by["New Bot"]["waiting"] is True
        assert "What should I help with first?" in by["New Bot"]["preview"]
        assert by["New Bot"]["shape"] == "cloud"
        assert by["New Bot"]["color"].upper() == "#FF9800"

        assert len(by["Clipped"]["preview"]) <= 140
        assert by["Clipped"]["preview"].startswith("A")

        print("messages ok · preview, waiting, avatars, clip, hidden stub skipped, transcript ignored")

    # Live roster on this machine, if present.
    live = json.loads(subprocess.check_output(["python3", str(ROOT / "inbox.py")]))
    assert live.get("ok") is True
    assert live.get("demo") is False
    for bot in live.get("bots") or []:
        assert bot.get("preview") is not None
        assert bot.get("name")
        if bot["name"] in ("Angela", "Laszlo", "New Bot"):
            assert bot["preview"] != ""
    print("live inbox ok · bots=%d" % len(live.get("bots") or []))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
