import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property url demoUrl: Qt.resolvedUrl("demo-roster.json")

  property var bots: []
  property bool demo: false
  property bool hasSnapshot: false
  property string lastError: ""
  property bool refreshing: false

  readonly property int maxInboxBytes: 65536
  readonly property int maxBots: 24
  readonly property bool useDemoRoster: boolSetting("useDemoRoster", true)

  readonly property string homeDir: {
    var home = Quickshell.env("HOME") || ""
    return (home !== "" && home.charAt(0) === "/") ? home : ""
  }
  readonly property string snapshotPath: homeDir !== "" ? homeDir + "/.local/state/glorics-grok-bots/inbox.json" : ""

  readonly property int botCount: bots.length
  readonly property int unreadCount: {
    var n = 0
    for (var i = 0; i < bots.length; i++)
      n += Number(bots[i] && bots[i].unread || 0)
    return n
  }
  readonly property int unreadBots: {
    var n = 0
    for (var i = 0; i < bots.length; i++)
      if (bots[i] && Number(bots[i].unread || 0) > 0) n++
    return n
  }
  readonly property int waitingCount: {
    var n = 0
    for (var i = 0; i < bots.length; i++)
      if (bots[i] && bots[i].waiting) n++
    return n
  }
  readonly property var attentionBots: {
    var out = []
    for (var i = 0; i < bots.length && out.length < 3; i++) {
      var b = bots[i]
      if (b && (b.waiting || Number(b.unread || 0) > 0 || b.busy))
        out.push(b)
    }
    return out
  }
  readonly property bool lively: unreadCount > 0 || waitingCount > 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (value === true || value === "true" || value === 1 || value === "1")
      return true
    if (value === false || value === "false" || value === 0 || value === "0")
      return false
    return fallback
  }

  function clip(s, n) {
    s = String(s || "")
    var out = ""
    for (var i = 0; i < s.length && out.length < n; i++) {
      var c = s.charCodeAt(i)
      if (c < 32 || c === 127 || c === 0x2028 || c === 0x2029)
        continue
      out += s.charAt(i)
    }
    return out
  }

  function allowIdent(s, maxLen) {
    s = clip(String(s || "").trim(), maxLen)
    if (s.length < 1)
      return ""
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      var ok = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch === "." || ch === "_" || ch === "-" || ch === ":"
      if (!ok)
        return ""
    }
    return s
  }

  function allowColor(s) {
    s = clip(String(s || "").trim(), 24)
    if (s.length < 4 || s.charAt(0) !== "#")
      return "#888888"
    for (var i = 1; i < s.length; i++) {
      var ch = s.charAt(i).toLowerCase()
      var ok = (ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f")
      if (!ok)
        return "#888888"
    }
    if (s.length !== 4 && s.length !== 7)
      return "#888888"
    return s
  }

  function allowShape(s) {
    s = String(s || "square").toLowerCase()
    if (s === "circle" || s === "square" || s === "pentagon" || s === "hexagon" || s === "blob")
      return s
    return "square"
  }

  function sanitizeBots(arr) {
    var out = []
    if (!arr || arr.length === undefined)
      return out
    var n = Math.min(arr.length, root.maxBots)
    for (var i = 0; i < n; i++) {
      var b = arr[i]
      if (!b || typeof b !== "object")
        continue
      var id = root.allowIdent(b.id, 80)
      if (id === "")
        continue
      var unread = parseInt(String(b.unread === true ? 1 : (b.unread || 0)), 10)
      if (!isFinite(unread) || unread < 0)
        unread = 0
      if (unread > 99)
        unread = 99
      out.push({
        id: id,
        name: root.clip(b.name, 80),
        team: root.clip(b.team, 40),
        preview: root.clip(b.preview, 140),
        when: root.clip(b.when, 16),
        unread: unread,
        waiting: b.waiting === true,
        busy: b.busy === true,
        activity: root.clip(b.activity, 40),
        shape: root.allowShape(b.shape),
        color: root.allowColor(b.color)
      })
    }
    return out
  }

  function applyInbox(text, fromDemo) {
    root.refreshing = false
    if (String(text || "").length > root.maxInboxBytes) {
      root.lastError = "inbox snapshot too large"
      root.hasSnapshot = false
      root.bots = []
      root.demo = false
      return
    }
    try {
      var data = JSON.parse(text)
      if (!data || data.ok !== true || data.client !== "glorics.grok-bots") {
        root.lastError = "Not a Grok Bots inbox snapshot"
        root.hasSnapshot = false
        root.bots = []
        root.demo = false
        return
      }
      root.bots = root.sanitizeBots(data.bots)
      root.demo = fromDemo === true || data.demo === true
      root.hasSnapshot = true
      root.lastError = ""
    } catch (e) {
      root.lastError = "Could not read inbox"
      root.hasSnapshot = false
      root.bots = []
      root.demo = false
    }
  }

  function refresh() {
    root.refreshing = true
    if (snapshotFile.path !== "")
      snapshotFile.reload()
    else
      loadDemo()
  }

  function loadDemo() {
    if (!root.useDemoRoster) {
      root.refreshing = false
      root.hasSnapshot = false
      root.demo = false
      root.bots = []
      root.lastError = ""
      return
    }
    demoFile.reload()
  }

  FileView {
    id: snapshotFile
    path: root.snapshotPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyInbox(text(), false)
    onFileChanged: snapshotFile.reload()
    onLoadFailed: root.loadDemo()
  }

  FileView {
    id: demoFile
    path: {
      var u = String(root.demoUrl)
      return u.indexOf("file://") === 0 ? decodeURIComponent(u.substring(7)) : ""
    }
    printErrors: false
    onLoaded: root.applyInbox(text(), true)
    onLoadFailed: {
      root.refreshing = false
      root.hasSnapshot = false
      root.demo = false
      root.bots = []
      root.lastError = "Could not read demo roster"
    }
  }

  Component.onCompleted: refresh()
}
