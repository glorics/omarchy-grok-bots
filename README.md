# Grok Bots for Omarchy

Unofficial community bar roster by **glorics**. It puts Grok Bot on the Omarchy bar the way a messenger does: a cluster of faces, unread counts, who is waiting on you, and one click into the [Grok Bot](https://x.ai/bot) Linux client.

This plugin is **not** Grok Bot, and it is **not** an xAI or Cursor product. It is a new project next to the listed launcher [`glorics.grok-bot`](https://plugins.omarchy.org/plugin.html?id=glorics.grok-bot). It does not replace that listing.

## What it does

- Themed x.ai/bot face on the bar, plus colored faces for bots that need you
- Unread badge on the hub
- Inbox panel: name, team, last preview, relative time, unread count
- Highlight for **waiting on you**
- Opens or focuses the Grok Bot Linux AppImage
- Shows whether the window is open
- Can check Cursor's update feed and, when you click **Update now**, install a Linux AppImage whose URL, size, and SHA-256 are pinned in this snapshot

It does not read Grok Bot tokens, cookies, `sand-secrets.json`, or transcript blobs. Live inbox rows come from the official client's **last-roster** slice under `~/.config/Grok Bot/sand-client-persistence` (names, last-message preview, unread, waiting-on-you). Click a row to open or focus the Linux client. There is no fake roster on the bar.

## External dependency

The [Grok Bot Linux client](https://x.ai/bot) (AppImage). Install it yourself, or use **Update now** in the panel for the pinned Cursor CDN artifact. Removing the plugin does not remove the AppImage.

## Install

Plugins run unsandboxed inside `omarchy-shell`. Read this repository first.

From this tree:

```bash
omarchy plugin add /home/manny/src/omarchy-grok-bots --enable
```

```bash
omarchy plugin remove glorics.grok-bots
```

Leave `glorics.grok-bot` installed if you still want the listed launcher.

## Inbox

The widget re-reads the official client's last-roster file about every five seconds, and again when that file changes. At most 24 bots. Previews are clipped. Transcript blobs are not opened.

The bar shows only the bots in your signed-in Grok Bot client.

## License

MIT for this plugin only. Grok Bot, the x.ai/bot mark, and the Linux AppImage belong to xAI / Cursor.
