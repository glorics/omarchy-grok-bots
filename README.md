# Grok Bots for Omarchy

Unofficial community bar roster by **glorics**. It puts your [Grok Bot](https://x.ai/bot) agents on the Omarchy bar: the same faces as in the app, last messages, unread bubbles, and one click into the Linux client.

This plugin is **not** Grok Bot, and it is **not** an xAI or Cursor product. It is a new plugin next to the listed launcher [`glorics.grok-bot`](https://plugins.omarchy.org/plugin.html?id=glorics.grok-bot). It does not replace that listing.

## What it does

- Hub face on the bar, plus a face for each of your bots
- Those faces use the **same shape and color as in Grok Bot** (custom face if you set one; otherwise Grok Bot's own default from the bot id)
- A small count bubble when a bot has unread messages
- Inbox panel: name, last preview, relative time, unread
- Click a row to open or focus the Grok Bot Linux client
- Status of the client window, optional pinned Cursor CDN AppImage update

It does not read tokens, cookies, `sand-secrets.json`, or transcript blobs. It only reads the official client's last-roster file under `~/.config/Grok Bot/sand-client-persistence` (names, last-message preview, unread, waiting-on-you, avatar shape and color).

## How to demo it

1. Install and enable the plugin (below). Keep Grok Bot itself installed.
2. Open the Grok Bot Linux app and sign in. You should see your real bots (for example Angela, Laszlo, New Bot).
3. Click the Grok cluster on the Omarchy bar. The panel lists those same bots. The yellow cloud, red tablet, and red triangle on the bar are the same faces as in the Grok Bot sidebar.
4. Click a row. The Grok Bot window opens or focuses.
5. In Grok Bot, change a bot's shape or color. Within a few seconds the bar face follows, because the widget re-reads the roster file when it changes.
6. When a bot has unread messages, a small bubble with the number sits on that face and on the inbox row.

There is no fake roster on the bar.

## External dependency

The [Grok Bot Linux client](https://x.ai/bot) (AppImage). Install it yourself, or use **Update now** in the panel for the pinned Cursor CDN artifact. Removing the plugin does not remove the AppImage. Marketplace listing is **manual-setup** because of that client.

## Install

Plugins run unsandboxed inside `omarchy-shell`. Read this repository first.

```bash
omarchy plugin add https://github.com/glorics/omarchy-grok-bots.git --enable
```

```bash
omarchy plugin remove glorics.grok-bots
```

The listed launcher `glorics.grok-bot` can stay installed. This plugin is a separate id.

## Inbox

The widget re-reads last-roster about every five seconds, and again when that file changes. At most 24 bots. Previews are clipped. Transcript blobs are not opened.

## License

MIT for this plugin only. Grok Bot, the x.ai/bot mark, and the Linux AppImage belong to xAI / Cursor.
