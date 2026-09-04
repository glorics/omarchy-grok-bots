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

It does not read Grok Bot tokens, chats, cookies, or Electron files under `~/.config/Grok Bot`. Live inbox rows come only from a snapshot you own at `~/.local/state/glorics-grok-bots/inbox.json`. Until that file exists, the bundled **demo roster** is shown and labeled as demo.

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

## Inbox snapshot

Optional. JSON, max 64 KiB, at most 24 bots. `client` must be `glorics.grok-bots`.

```json
{
  "ok": true,
  "client": "glorics.grok-bots",
  "demo": false,
  "bots": [
    {
      "id": "chief-of-staff",
      "name": "Chief of Staff",
      "team": "Operations",
      "preview": "Your Thursday is triple-booked.",
      "when": "35m",
      "unread": 0,
      "waiting": true,
      "shape": "square",
      "color": "#e23d3d"
    }
  ]
}
```

Turn off **Show bundled demo roster** in plugin settings if you want an empty inbox instead of the demo.

## License

MIT for this plugin only. Grok Bot, the x.ai/bot mark, and the Linux AppImage belong to xAI / Cursor.
