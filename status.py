#!/usr/bin/env python3
"""Local status for the Grok Bot Linux client.

Cheap path (default): local files and Hyprland. Does not touch the network.
`--fetch` asks Cursor's update API what the current Grok Bot version is, then
looks for a Linux AppImage of that version on the Cursor CDN.
`--update` downloads that AppImage when one is newer than the install.

Does not read Grok Bot tokens, chats, or secret files.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import select
import shutil
import signal
import ssl
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

PLUGIN_REPO = os.environ.get("GROKBOT_PLUGIN_REPO", "glorics/omarchy-grok-bot")
HOME = Path.home()
STATE_DIR = Path(os.environ.get("GROKBOT_STATE", str(HOME / ".grokbot")))
STATE_FILE = STATE_DIR / "installed"
LATEST_CACHE = STATE_DIR / "latest-official.json"
APPIMAGE = Path(
    os.environ.get(
        "GROKBOT_APPIMAGE", str(HOME / "Applications" / "GrokBot-current.AppImage")
    )
)
APPS = Path(os.environ.get("GROKBOT_APPS", str(HOME / "Applications")))
CONFIG_DIR = HOME / ".config" / "Grok Bot"
MARKER_FILE = CONFIG_DIR / "sand-session-marker.json"
SESSION_HINTS = (
    MARKER_FILE,
    CONFIG_DIR / "window-state.json",
    CONFIG_DIR / "gateway-descriptor.json",
)
PRODUCT_URL = "https://x.ai/bot"
PLUGIN_URL = f"https://github.com/{PLUGIN_REPO}"
DARWIN_PROBE = (
    "https://api2.cursor.sh/updates/download/stable/darwin-arm64/"
    "grok-bot-bd824e1890d8b96f"
)
# Only these exact artifacts may be written executable. A newer Cursor
# build without a digest in this snapshot fails closed.
PINNED_APPIMAGES = {
    "0.30.0": {
        "url": (
            "https://downloads.cursor.com/grokbot/stable/"
            "2385d097738b3719cc5ecd9281a107aa106215f1/linux/x64/Grok_Bot_0.30.0.AppImage"
        ),
        "sha256": "1adf717784138d8945b248001805a9ae45a77c44aeed2004d81df3a3b2f40bc2",
        "bytes": 131344546,
    },
}
OFFICIAL_APPIMAGE_URL = PINNED_APPIMAGES["0.30.0"]["url"]
STALE_AFTER_MS = 45_000
VERSION_RE = re.compile(r"Grok_Bot_(\d+\.\d+\.\d+)")
MAX_PROC_BYTES = 64 * 1024
MAX_FILE_BYTES = 64 * 1024
MAX_HYPR_BYTES = 1024 * 1024
MAX_STDOUT_BYTES = 256 * 1024
MAX_FIELD = 96
MAX_APPIMAGE_BYTES = 200 * 1024 * 1024
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
O_CLOEXEC = getattr(os, "O_CLOEXEC", 0)
CURRENT_NAME = "GrokBot-current.AppImage"


def clip(value, n: int = MAX_FIELD) -> str:
    text = str(value or "")
    return text if len(text) <= n else text[:n]


def kill_tree(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except OSError:
        try:
            proc.send_signal(signal.SIGTERM)
        except OSError:
            pass
    try:
        proc.wait(timeout=0.2)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except OSError:
        try:
            proc.kill()
        except OSError:
            pass
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass


def run(cmd: list[str], timeout: int = 8, max_bytes: int = MAX_PROC_BYTES) -> subprocess.CompletedProcess:
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
            bufsize=0,
            start_new_session=True,
            close_fds=True,
        )
    except OSError as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))

    stdout = bytearray()
    stderr = bytearray()
    streams = {}
    if proc.stdout:
        streams[proc.stdout] = stdout
    if proc.stderr:
        streams[proc.stderr] = stderr
    overflow = False
    deadline = time.monotonic() + max(0.05, float(timeout))
    try:
        while streams:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            ready, _, _ = select.select(list(streams), [], [], remaining)
            if not ready:
                break
            stop = False
            for fh in ready:
                buf = streams[fh]
                try:
                    chunk = os.read(fh.fileno(), 4096)
                except OSError:
                    chunk = b""
                if not chunk:
                    try:
                        fh.close()
                    except OSError:
                        pass
                    streams.pop(fh, None)
                    continue
                room = max_bytes - len(buf)
                if room <= 0 or len(chunk) > room:
                    if room > 0:
                        buf.extend(chunk[:room])
                    overflow = True
                    stop = True
                    break
                buf.extend(chunk)
            if stop:
                break
        if proc.poll() is None:
            kill_tree(proc)
    finally:
        for fh in (proc.stdout, proc.stderr):
            if fh and not fh.closed:
                try:
                    fh.close()
                except OSError:
                    pass

    code = proc.returncode if proc.returncode is not None else 1
    if overflow and code == 0:
        code = 1
    return subprocess.CompletedProcess(
        cmd,
        code,
        bytes(stdout).decode("utf-8", errors="replace"),
        bytes(stderr).decode("utf-8", errors="replace"),
    )


def emit(obj: dict) -> None:
    raw = json.dumps(obj, ensure_ascii=True)
    if len(raw.encode("utf-8")) > MAX_STDOUT_BYTES:
        raw = json.dumps({"ok": False, "error": "Output too large"}, ensure_ascii=True)
    sys.stdout.write(raw)


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


def open_dir_walk(path: Path, *, create: bool = False, leaf_mode: int | None = 0o700) -> int:
    """Walk path from / with O_NOFOLLOW. Refuse unsafe entries; never delete them."""
    parts = _path_parts(path)
    home_parts = _path_parts(HOME)
    flags = os.O_RDONLY | os.O_DIRECTORY | O_CLOEXEC
    nofollow = flags | O_NOFOLLOW
    fd = os.open("/", flags)
    try:
        for i, name in enumerate(parts):
            is_leaf = i == len(parts) - 1
            under_home = parts[: i + 1][: len(home_parts)] == home_parts and (i + 1) > len(home_parts)
            try:
                nxt = os.open(name, nofollow, dir_fd=fd)
            except FileNotFoundError:
                if not (create and under_home):
                    raise
                if is_leaf and leaf_mode is not None:
                    mkdir_mode = leaf_mode
                elif is_leaf:
                    mkdir_mode = 0o755
                else:
                    mkdir_mode = 0o700
                os.mkdir(name, mkdir_mode, dir_fd=fd)
                nxt = os.open(name, nofollow, dir_fd=fd)
            os.close(fd)
            fd = nxt
            st = os.fstat(fd)
            if not stat.S_ISDIR(st.st_mode):
                raise OSError("not a directory")
            if is_leaf:
                if st.st_uid != os.getuid():
                    raise OSError("not owner")
                if leaf_mode is not None:
                    os.fchmod(fd, leaf_mode)
        return fd
    except Exception:
        os.close(fd)
        raise


def ensure_private_dir(path: Path, *, leaf_mode: int | None = 0o700) -> bool:
    try:
        fd = open_dir_walk(path, create=True, leaf_mode=leaf_mode)
    except OSError:
        return False
    os.close(fd)
    return True


def ensure_state_dir() -> bool:
    return ensure_private_dir(STATE_DIR, leaf_mode=0o700)


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


def _atomic_write_at(dir_fd: int, name: str, data: bytes, max_bytes: int, mode: int = 0o600) -> bool:
    if not _basename_ok(name) or len(data) > max_bytes:
        return False
    try:
        dest = os.open(name, os.O_RDONLY | O_NOFOLLOW | O_CLOEXEC, dir_fd=dir_fd)
    except FileNotFoundError:
        dest = -1
    except OSError:
        return False
    if dest >= 0:
        try:
            st = os.fstat(dest)
            if not stat.S_ISREG(st.st_mode):
                return False
        finally:
            os.close(dest)
    tmp = ".tmp-" + secrets.token_hex(8)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | O_NOFOLLOW | O_CLOEXEC
    try:
        fd = os.open(tmp, flags, 0o600, dir_fd=dir_fd)
    except OSError:
        return False
    try:
        view = memoryview(data)
        written = 0
        while written < len(data):
            n = os.write(fd, view[written:])
            if n <= 0:
                raise OSError("short write")
            written += n
        os.fsync(fd)
        os.fchmod(fd, mode)
    except OSError:
        os.close(fd)
        try:
            os.unlink(tmp, dir_fd=dir_fd)
        except OSError:
            pass
        return False
    os.close(fd)
    try:
        os.rename(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        os.fsync(dir_fd)
        return True
    except OSError:
        try:
            os.unlink(tmp, dir_fd=dir_fd)
        except OSError:
            pass
        return False


def read_bounded(path: Path, max_bytes: int) -> bytes:
    if path.parent == STATE_DIR:
        try:
            dir_fd = open_dir_walk(STATE_DIR, create=False, leaf_mode=0o700)
        except OSError:
            return b""
        try:
            return _read_at(dir_fd, path.name, max_bytes)
        finally:
            os.close(dir_fd)
    flags = os.O_RDONLY | O_NOFOLLOW | O_CLOEXEC
    try:
        fd = os.open(str(path), flags)
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


def atomic_write(path: Path, text: str) -> None:
    if path.parent != STATE_DIR:
        return
    data = text.encode("utf-8")
    if len(data) > MAX_FILE_BYTES:
        return
    try:
        dir_fd = open_dir_walk(STATE_DIR, create=True, leaf_mode=0o700)
    except OSError:
        return
    try:
        _atomic_write_at(dir_fd, path.name, data, MAX_FILE_BYTES, 0o600)
    finally:
        os.close(dir_fd)


def read_kv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    raw = read_bounded(path, MAX_FILE_BYTES)
    if not raw:
        return out
    try:
        text = raw.decode("utf-8")
    except UnicodeError:
        return out
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def read_json(path: Path) -> dict:
    raw = read_bounded(path, MAX_FILE_BYTES)
    if not raw:
        return {}
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def write_json(path: Path, data: dict) -> None:
    atomic_write(path, json.dumps(data, indent=2) + "\n")


def strip_v(value: str) -> str:
    text = str(value or "").strip()
    if text.lower().startswith("v") and len(text) > 1 and text[1].isdigit():
        return text[1:]
    return text


def version_tuple(value: str) -> tuple[int, ...]:
    text = strip_v(value)
    parts: list[int] = []
    for piece in text.replace("-", ".").split("."):
        if piece.isdigit():
            parts.append(int(piece))
        else:
            break
    return tuple(parts)


def version_newer(latest: str, installed: str) -> bool:
    left = version_tuple(latest)
    right = version_tuple(installed)
    if not left or not right:
        return False
    n = max(len(left), len(right))
    left += (0,) * (n - len(left))
    right += (0,) * (n - len(right))
    return left > right


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    return Path(f"/proc/{pid}").exists()


def which_grok_bot() -> str:
    found = shutil.which("grok-bot")
    return found or ""


def package_version() -> str:
    proc = run(["pacman", "-Q", "grok-bot"], timeout=2)
    if proc.returncode != 0:
        return ""
    parts = proc.stdout.strip().split()
    if len(parts) < 2:
        return ""
    return parts[1].split("-", 1)[0]


def hypr_window() -> dict:
    proc = run(["hyprctl", "clients", "-j"], timeout=2, max_bytes=MAX_HYPR_BYTES)
    if proc.returncode != 0 or not proc.stdout.strip():
        return {}
    try:
        clients = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}
    for client in clients or []:
        klass = str(client.get("class") or "").lower()
        title = str(client.get("title") or "")
        if klass in ("grok-bot", "sand"):
            return {
                "class": str(client.get("class") or ""),
                "title": clip(title, 80),
                "pid": int(client.get("pid") or 0),
            }
    return {}


def appimage_present() -> bool:
    if APPIMAGE.is_symlink() or APPIMAGE.is_file():
        return APPIMAGE.exists()
    return False


def curl_headers(url: str, timeout: int = 12) -> str:
    proc = run(
        [
            "curl",
            "-sI",
            "-L",
            "--max-redirs",
            "5",
            "-A",
            "Mozilla/5.0",
            "--max-time",
            str(timeout),
            url,
        ],
        timeout=timeout + 2,
    )
    return clip(proc.stdout or "", MAX_PROC_BYTES)


def head_ok(url: str) -> bool:
    proc = run(
        [
            "curl",
            "-sI",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "-A",
            "Mozilla/5.0",
            "--max-time",
            "10",
            url,
        ],
        timeout=12,
    )
    return proc.stdout.strip() == "200"


def pinned_artifact(version: str) -> dict:
    pin = PINNED_APPIMAGES.get(strip_v(version) or "")
    return pin if isinstance(pin, dict) else {}


def linux_url_for(version: str) -> str:
    pin = pinned_artifact(version)
    url = str(pin.get("url") or "")
    if url and head_ok(url):
        return url
    return ""


def ago_text(epoch: float) -> str:
    if epoch <= 0:
        return ""
    seconds = max(0, int(time.time() - epoch))
    if seconds < 45:
        return "just now"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m ago"
    hours = minutes // 60
    if hours < 48:
        return f"{hours}h ago"
    return f"{hours // 24}d ago"


def notify(summary: str, body: str) -> None:
    icon = HOME / ".local/share/pixmaps/grok-bot.png"
    cmd = [
        "notify-send",
        "-a",
        "Grok Bot",
        "-u",
        "normal",
        "-h",
        "string:x-canonical-private-synchronous:grok-bot-update",
        "-i",
        str(icon) if icon.exists() else "grok-bot",
        summary,
        body,
    ]
    run(cmd, timeout=3)


def fetch_latest() -> dict:
    headers = curl_headers(DARWIN_PROBE)
    latest = ""
    match = VERSION_RE.search(headers)
    if match:
        latest = match.group(1)
    linux = linux_url_for(latest) if latest else ""
    prev = read_json(LATEST_CACHE)
    last_notified = strip_v(str(prev.get("lastNotified") or ""))
    installed = strip_v(read_kv(STATE_FILE).get("tag") or "")
    if latest and installed and version_newer(latest, installed) and latest != last_notified:
        if linux:
            notify(
                f"Grok Bot {latest} is out",
                "Linux AppImage is on the Cursor CDN. Open the bar plugin to update.",
            )
        else:
            notify(
                f"Grok Bot {latest} is out",
                "A newer desktop build exists. No Linux AppImage on the CDN yet.",
            )
        last_notified = latest
    data = {
        "tag": latest,
        "linuxUrl": linux,
        "checkedAt": time.time(),
        "lastNotified": last_notified,
    }
    write_json(LATEST_CACHE, data)
    return data


def _replace_current_symlink(dir_fd: int, target_name: str) -> bool:
    if not _basename_ok(target_name):
        return False
    try:
        st = os.lstat(CURRENT_NAME, dir_fd=dir_fd)
    except FileNotFoundError:
        os.symlink(target_name, CURRENT_NAME, dir_fd=dir_fd)
        os.fsync(dir_fd)
        return True
    except OSError:
        return False
    if not stat.S_ISLNK(st.st_mode):
        return False
    try:
        existing = os.readlink(CURRENT_NAME, dir_fd=dir_fd)
    except OSError:
        return False
    if existing != os.path.basename(existing):
        return False
    try:
        os.unlink(CURRENT_NAME, dir_fd=dir_fd)
        os.symlink(target_name, CURRENT_NAME, dir_fd=dir_fd)
        os.fsync(dir_fd)
        return True
    except OSError:
        return False


def _fd_sha256_and_elf(fd: int, expected_bytes: int) -> tuple[str, bool]:
    digest = hashlib.sha256()
    os.lseek(fd, 0, os.SEEK_SET)
    total = 0
    magic = b""
    while True:
        chunk = os.read(fd, 1024 * 64)
        if not chunk:
            break
        if total == 0:
            magic = chunk[:4]
        total += len(chunk)
        if total > expected_bytes:
            return "", False
        digest.update(chunk)
    if total != expected_bytes:
        return "", False
    return digest.hexdigest(), magic == b"\x7fELF"


def _download_pinned(dir_fd: int, tmp_name: str, pin: dict, timeout: int = 300) -> bool:
    url = str(pin.get("url") or "")
    expected = int(pin.get("bytes") or 0)
    want = str(pin.get("sha256") or "")
    if not url.startswith("https://downloads.cursor.com/grokbot/stable/") or expected < 1 or len(want) != 64:
        return False
    if expected > MAX_APPIMAGE_BYTES:
        return False
    flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | O_NOFOLLOW | O_CLOEXEC
    try:
        fd = os.open(tmp_name, flags, 0o600, dir_fd=dir_fd)
    except OSError:
        return False
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})

    class _NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None

    opener = urllib.request.build_opener(_NoRedirect, urllib.request.HTTPSHandler(context=ctx))
    digest = hashlib.sha256()
    total = 0
    deadline = time.monotonic() + timeout
    try:
        with opener.open(req, timeout=timeout) as resp:
            if getattr(resp, "geturl", lambda: url)() != url:
                raise OSError("redirect")
            length = resp.headers.get("Content-Length")
            if length is not None:
                try:
                    if int(length) != expected:
                        raise ValueError("size")
                except ValueError:
                    raise OSError("bad length")
            while True:
                if time.monotonic() > deadline:
                    raise TimeoutError
                chunk = resp.read(1024 * 64)
                if not chunk:
                    break
                total += len(chunk)
                if total > expected:
                    raise OSError("too large")
                digest.update(chunk)
                os.write(fd, chunk)
        if total != expected or digest.hexdigest() != want:
            raise OSError("digest")
        os.fsync(fd)
        got, elf = _fd_sha256_and_elf(fd, expected)
        if got != want or not elf:
            raise OSError("verify")
        os.fchmod(fd, 0o755)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        return True
    except (OSError, TimeoutError, urllib.error.URLError, ssl.SSLError, ValueError):
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass
        try:
            os.unlink(tmp_name, dir_fd=dir_fd)
        except OSError:
            pass
        return False


def do_update() -> int:
    cache = fetch_latest()
    latest = strip_v(str(cache.get("tag") or ""))
    pin = pinned_artifact(latest)
    state = read_kv(STATE_FILE)
    installed = strip_v(state.get("tag") or "")
    if not latest:
        print("Could not reach Cursor's update feed", file=sys.stderr)
        return 1
    if installed and not version_newer(latest, installed):
        print(f"Up to date · {installed}")
        return 0
    if not pin:
        print(
            f"Newer Grok Bot {latest} is out, but this plugin snapshot has no pinned digest",
            file=sys.stderr,
        )
        return 2
    name = f"Grok_Bot_{latest}.AppImage"
    if not _basename_ok(name):
        print("Bad AppImage name", file=sys.stderr)
        return 1
    try:
        dir_fd = open_dir_walk(APPS, create=True, leaf_mode=None)
    except OSError:
        print("Could not open ~/Applications", file=sys.stderr)
        return 1
    tmp = ".partial-" + secrets.token_hex(8)
    try:
        if not _download_pinned(dir_fd, tmp, pin):
            print("Download failed digest or size check", file=sys.stderr)
            return 1
        try:
            os.rename(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
            os.fsync(dir_fd)
        except OSError:
            try:
                os.unlink(tmp, dir_fd=dir_fd)
            except OSError:
                pass
            print("Could not install AppImage", file=sys.stderr)
            return 1
        if not _replace_current_symlink(dir_fd, name):
            print("Installed AppImage, but current symlink was unsafe", file=sys.stderr)
            return 1
    finally:
        os.close(dir_fd)
    atomic_write(
        STATE_FILE,
        "\n".join(
            [
                f"tag={latest}",
                f"name={name}",
                f"path={APPS / CURRENT_NAME}",
                "source=official-cursor-cdn",
                f"url={pin['url']}",
                f"sha256={pin['sha256']}",
                "",
            ]
        )
        + "\n",
    )
    print(f"installed {latest}")
    return 0


def status() -> dict:
    state = read_kv(STATE_FILE)
    marker = read_json(MARKER_FILE)
    cache = read_json(LATEST_CACHE)
    window = hypr_window()
    launcher = which_grok_bot()
    pkg = package_version()
    installed_version = strip_v(state.get("tag") or "")
    app_version = strip_v(str(marker.get("appVersion") or ""))
    download_url = state.get("url") or OFFICIAL_APPIMAGE_URL
    state_source = state.get("source") or ""
    latest = strip_v(str(cache.get("tag") or ""))
    linux_latest = str(cache.get("linuxUrl") or "")
    checked_at = float(cache.get("checkedAt") or 0)

    source = "none"
    source_label = "Not installed"
    if appimage_present() or state_source == "official-cursor-cdn" or (
        launcher.endswith("/.local/bin/grok-bot") and state
    ):
        source = "official"
        source_label = "Linux AppImage"
        if not installed_version:
            installed_version = app_version
    elif pkg:
        source = "package"
        source_label = "Omarchy package"
        if not installed_version:
            installed_version = pkg
    elif launcher:
        source = "path"
        source_label = "grok-bot on PATH"

    installed = source != "none"
    version = app_version or installed_version or pkg

    pid = int(marker.get("pid") or 0)
    if pid <= 0 and window.get("pid"):
        pid = int(window["pid"])
    running_proc = pid_alive(pid)
    running_window = bool(window)
    running = running_proc or running_window

    alive_at = int(marker.get("aliveAtMs") or 0)
    now_ms = int(time.time() * 1000)
    stale_ms = max(0, now_ms - alive_at) if alive_at else 0
    crash_seen = bool(marker.get("crashSeen"))
    crashed = (not running) and (
        crash_seen or (alive_at > 0 and stale_ms > STALE_AFTER_MS and pid > 0)
    )

    if source == "official":
        launch = (
            "uwsm-app -- grok-bot"
            if launcher
            else f"uwsm-app -- {APPIMAGE} --class=grok-bot --ozone-platform-hint=auto"
        )
        focus = "grok-bot"
    elif source == "package":
        launch = "uwsm-app -- grok-bot"
        focus = window.get("class") or "sand"
    elif source == "path":
        launch = f"uwsm-app -- {launcher}"
        focus = window.get("class") or "grok-bot"
    else:
        launch = ""
        focus = "grok-bot"

    if window.get("class"):
        focus = str(window["class"])

    if not installed:
        status_text = "Not installed"
    elif crashed:
        status_text = "Crashed"
    elif running:
        status_text = "Connected"
    else:
        status_text = "Window closed"

    signed_in = any(path.exists() for path in SESSION_HINTS)
    # Darwin/desktop can be newer than Linux. Only flag an update when this
    # snapshot pins a Linux AppImage we can actually install.
    linux_ready = bool(latest and pinned_artifact(latest) and linux_latest)
    update_available = bool(
        linux_ready and version and version_newer(latest, version)
    )
    can_update = update_available
    display_latest = latest if linux_ready else (version or latest)

    return {
        "ok": True,
        "installed": installed,
        "source": source,
        "sourceLabel": source_label,
        "running": running,
        "crashed": crashed,
        "pid": pid if running else 0,
        "windowClass": window.get("class") or focus,
        "windowTitle": clip(window.get("title") or "", 80),
        "installedVersion": clip(installed_version or pkg, 32),
        "appVersion": clip(version, 32),
        "latestVersion": clip(display_latest, 32),
        "updateAvailable": update_available,
        "canSelfUpdate": can_update,
        "linuxUpdateUrl": linux_latest if can_update else "",
        "launcher": launcher,
        "appImage": str(APPIMAGE) if appimage_present() else "",
        "launchCommand": launch,
        "focusPattern": focus,
        "repo": PLUGIN_REPO,
        "githubUrl": PLUGIN_URL,
        "releasesUrl": download_url,
        "productUrl": PRODUCT_URL,
        "statusText": status_text,
        "computerLabel": "Always on",
        "signedIn": signed_in,
        "signedInLabel": "Yes" if signed_in else "No",
        "lastCheckText": ago_text(checked_at),
        "staleSeconds": int(stale_ms / 1000) if stale_ms else 0,
        "packageVersion": pkg,
    }


def main() -> int:
    args = sys.argv[1:]
    if "--update" in args:
        return do_update()
    if "--fetch" in args:
        fetch_latest()
    emit(status())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
