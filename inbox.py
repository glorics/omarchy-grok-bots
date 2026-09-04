#!/usr/bin/env python3
"""Read the Grok Bot Linux client's local roster snapshot.

Walks ~/.config/Grok Bot/sand-client-persistence with O_NOFOLLOW. Reads only
the last-roster slice (names, last-message preview, unread, waiting). Does
not read tokens, cookies, secrets, or transcript blobs.
"""

from __future__ import annotations

import base64
import json
import os
import stat
import sys
import time
from pathlib import Path

HOME = Path.home()
CONFIG_DIR = HOME / ".config" / "Grok Bot"
PERSIST_DIR = CONFIG_DIR / "sand-client-persistence"
MAX_FILE_BYTES = 64 * 1024
MAX_STDOUT_BYTES = 256 * 1024
MAX_BOTS = 24
MAX_FIELD = 140
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
O_CLOEXEC = getattr(os, "O_CLOEXEC", 0)

# Same tables and id-hash Grok Bot 0.30.0 uses when a bot has no custom face.
COLORS = {
    "black": "#000000",
    "brown": "#936439",
    "red": "#FF263C",
    "orange": "#FF6700",
    "yellow": "#FF9800",
    "green": "#00C972",
    "cyan": "#00BCA6",
    "blue": "#1084FE",
    "violet": "#9159FE",
    "magenta": "#FF309B",
    "gray": "#777777",
}
ALL_SHAPES = [
    "blob", "pebble", "bean", "egg", "squircle", "tablet", "capsule",
    "cylinder", "hex", "gem", "crystal", "wedge", "shield", "dome",
    "arch", "cloud", "teardrop", "leaf",
]
DEFAULT_SHAPES = ["blob", "pebble", "squircle", "tablet", "wedge", "hex", "cloud", "teardrop"]
DEFAULT_COLORS = ["brown", "red", "orange", "yellow", "green", "cyan", "blue", "violet", "magenta", "gray"]


def clip(value, n: int = MAX_FIELD) -> str:
    text = str(value or "")
    out = []
    for ch in text:
        code = ord(ch)
        if code < 32 or code == 127 or code in (0x2028, 0x2029):
            continue
        out.append(ch)
        if len(out) >= n:
            break
    return "".join(out)


def emit(obj: dict) -> None:
    raw = json.dumps(obj, ensure_ascii=True)
    if len(raw.encode("utf-8")) > MAX_STDOUT_BYTES:
        raw = json.dumps(
            {"ok": False, "client": "glorics.grok-bots", "error": "Output too large"},
            ensure_ascii=True,
        )
    sys.stdout.write(raw)


def empty(error: str = "") -> dict:
    out = {
        "ok": True,
        "client": "glorics.grok-bots",
        "demo": False,
        "sourcePath": "",
        "bots": [],
    }
    if error:
        out["error"] = clip(error, 80)
    return out


def _path_parts(path: Path) -> list[str]:
    raw = os.path.abspath(str(path))
    parts: list[str] = []
    for piece in raw.split(os.sep):
        if piece in ("", "."):
            continue
        if piece == "..":
            if parts:
                parts.pop()
            continue
        if "\x00" in piece:
            raise OSError("bad path")
        parts.append(piece)
    return parts


def _basename_ok(name: str) -> bool:
    return bool(name) and name not in (".", "..") and "/" not in name and "\x00" not in name


def open_dir_walk(path: Path) -> int:
    parts = _path_parts(path)
    flags = os.O_RDONLY | os.O_DIRECTORY | O_CLOEXEC
    nofollow = flags | O_NOFOLLOW
    fd = os.open("/", flags)
    try:
        for i, name in enumerate(parts):
            nxt = os.open(name, nofollow, dir_fd=fd)
            os.close(fd)
            fd = nxt
            st = os.fstat(fd)
            if not stat.S_ISDIR(st.st_mode):
                raise OSError("not a directory")
            if i == len(parts) - 1 and st.st_uid != os.getuid():
                raise OSError("not owner")
        return fd
    except Exception:
        os.close(fd)
        raise


def _read_at(dir_fd: int, name: str, max_bytes: int) -> bytes:
    if not _basename_ok(name):
        return b""
    try:
        fd = os.open(name, os.O_RDONLY | O_NOFOLLOW | O_CLOEXEC, dir_fd=dir_fd)
    except OSError:
        return b""
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1 or st.st_size > max_bytes:
            return b""
        data = os.read(fd, max_bytes + 1)
        if len(data) > max_bytes:
            return b""
        return data
    finally:
        os.close(fd)


def decode_slice_name(stem: str) -> str:
    if not stem or len(stem) > 400:
        return ""
    pad = "=" * ((8 - len(stem) % 8) % 8)
    try:
        raw = base64.b32decode(stem.upper() + pad, casefold=True)
        text = raw.decode("ascii")
    except Exception:
        return ""
    if ".." in text or "/" in text:
        return ""
    return text


def u32(n: int) -> int:
    return n & 0xFFFFFFFF


def i32(n: int) -> int:
    n = u32(n)
    return n - 2**32 if n >= 2**31 else n


def imul(a: int, b: int) -> int:
    return u32(u32(a) * u32(b))


def fnv1a(text: str) -> int:
    h = 2166136261
    for ch in text:
        h ^= ord(ch)
        h = imul(h, 16777619)
    return u32(h)


def shape_hash(bot_id: str) -> int:
    e = i32(fnv1a(bot_id))
    e = imul(e ^ (u32(e) >> 16), 73244475)
    e = imul(e ^ (u32(e) >> 13), 3266489909)
    return u32(e ^ (u32(e) >> 16))


def mulberry32(seed: int):
    e = u32(seed)

    def rng() -> float:
        nonlocal e
        e = u32(i32(e) + 1831565813)
        n = imul(e ^ (e >> 15), 1 | e)
        n = u32(i32(n) + i32(imul(n ^ (n >> 7), 61 | n))) ^ n
        n = u32(n)
        return u32(n ^ (n >> 14)) / 4294967296.0

    return rng


def color_from_id(bot_id: str) -> str:
    seed = u32(fnv1a(bot_id) ^ imul(1, 2654435769))
    seed = u32(seed ^ imul(1, 2654435769))
    idx = int(mulberry32(seed)() * len(DEFAULT_COLORS))
    if idx < 0 or idx >= len(DEFAULT_COLORS):
        return "gray"
    return DEFAULT_COLORS[idx]


def shape_from_id(bot_id: str) -> str:
    return DEFAULT_SHAPES[shape_hash(bot_id) % len(DEFAULT_SHAPES)]


def resolve_shape(row: dict, bot_id: str) -> str:
    if row.get("isGroup") is True:
        return "group"
    key = str(row.get("avatarShape") or "").strip().lower()
    if key in ALL_SHAPES:
        return key
    return shape_from_id(bot_id)


def resolve_color(row: dict, bot_id: str) -> str:
    key = str(row.get("avatarColor") or "").strip().lower()
    if key == "grey":
        key = "gray"
    if key in COLORS:
        return COLORS[key]
    return COLORS[color_from_id(bot_id)]


def relative_time(ms) -> str:
    try:
        stamp = float(ms)
    except (TypeError, ValueError):
        return ""
    if stamp <= 0:
        return ""
    if stamp > 1e12:
        stamp = stamp / 1000.0
    delta = max(0, int(time.time() - stamp))
    if delta < 60:
        return "now"
    if delta < 3600:
        return f"{delta // 60}m"
    if delta < 86400:
        return f"{delta // 3600}h"
    days = delta // 86400
    if days < 14:
        return f"{days}d"
    return f"{days // 7}w"


def waiting_flag(value) -> bool:
    if value is True:
        return True
    if value in (False, None, "", 0, "0", "false", "False"):
        return False
    return True


def preview_text(row: dict) -> str:
    entry = row.get("lastEntry")
    if isinstance(entry, dict):
        text = clip(entry.get("text"), 140)
        if text:
            return text
    title = clip(row.get("title"), 140)
    if title:
        return title
    return clip(row.get("description"), 140)


def team_text(row: dict) -> str:
    title = clip(row.get("title"), 40)
    if title:
        return title
    desc = clip(row.get("description"), 40)
    if ":" in desc:
        desc = desc.split(":", 1)[0].strip()
    return desc


def is_blank_stub(row: dict) -> bool:
    name = str(row.get("name") or "").strip().lower()
    if row.get("lastEntry") or clip(row.get("description")):
        return False
    return name in ("", "new bot", "(unnamed)")


def sanitize_row(row: dict) -> dict | None:
    if not isinstance(row, dict):
        return None
    if row.get("isHiddenFromSidebar") is True:
        return None
    if is_blank_stub(row):
        return None
    ident = clip(row.get("id"), 80)
    if not ident:
        return None
    for ch in ident:
        ok = ch.isalnum() or ch in "._-:"
        if not ok:
            return None
    unread = row.get("unreadCount")
    if row.get("hasUnread") is True and not unread:
        unread = 1
    try:
        unread_n = int(unread or 0)
    except (TypeError, ValueError):
        unread_n = 0
    if unread_n < 0:
        unread_n = 0
    if unread_n > 99:
        unread_n = 99
    activity_ms = row.get("lastActivityAt") or row.get("updatedAt") or 0
    return {
        "id": ident,
        "name": clip(row.get("name") or "Bot", 80),
        "team": team_text(row),
        "preview": preview_text(row),
        "when": relative_time(activity_ms),
        "unread": unread_n,
        "waiting": waiting_flag(row.get("awaitingUserResponse")),
        "busy": False,
        "activity": "",
        "shape": resolve_shape(row, ident),
        "color": resolve_color(row, ident),
        "activityAt": int(activity_ms or 0),
    }


def load_roster() -> dict:
    try:
        dir_fd = open_dir_walk(PERSIST_DIR)
    except FileNotFoundError:
        return empty()
    except OSError:
        return empty("Could not open Grok Bot state")
    try:
        try:
            names = os.listdir(dir_fd)
        except OSError:
            return empty("Could not list Grok Bot state")
        found: list[tuple[int, str, dict]] = []
        for name in names:
            if not name.endswith(".blob") or not _basename_ok(name):
                continue
            slice_name = decode_slice_name(name[:-5])
            if not slice_name.endswith(".roster.last-roster"):
                continue
            if "transcript" in slice_name:
                continue
            raw = _read_at(dir_fd, name, MAX_FILE_BYTES)
            if not raw:
                continue
            try:
                data = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
                continue
            if not isinstance(data, dict) or int(data.get("schemaVersion") or 0) < 1:
                continue
            value = data.get("value")
            rows = value.get("rows") if isinstance(value, dict) else None
            if not isinstance(rows, list):
                continue
            try:
                fd = os.open(name, os.O_RDONLY | O_NOFOLLOW | O_CLOEXEC, dir_fd=dir_fd)
            except OSError:
                mtime = 0
            else:
                try:
                    mtime = int(os.fstat(fd).st_mtime)
                finally:
                    os.close(fd)
            found.append((mtime, os.path.join(str(PERSIST_DIR), name), data))
        if not found:
            return empty()
        found.sort(reverse=True)
        _mtime, source, data = found[0]
        rows = data["value"]["rows"]
        bots = []
        for row in rows[:MAX_BOTS]:
            item = sanitize_row(row)
            if item:
                bots.append(item)
        bots.sort(key=lambda b: (not b["waiting"], b["unread"] <= 0, -int(b.get("activityAt") or 0)))
        for bot in bots:
            bot.pop("activityAt", None)
        return {
            "ok": True,
            "client": "glorics.grok-bots",
            "demo": False,
            "sourcePath": source,
            "bots": bots,
        }
    finally:
        os.close(dir_fd)


def main() -> int:
    emit(load_roster())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
