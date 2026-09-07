import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  property var bots: []
  property int stamp: 0
  property alias botsModel: botList
  property bool demo: false
  property bool hasSnapshot: false
  property string lastError: ""
  property bool refreshing: false
  property string sourcePath: ""

  ListModel {
    id: botList
  }

  ListModel {
    id: chatList
  }

  property alias chatModel: chatList
  property bool live: false
  property bool _pending: false
  property string focusedId: ""
  property string focusedName: ""

  readonly property int maxInboxBytes: 65536
  readonly property int maxBots: 24
  readonly property bool useDemoRoster: false

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
    var ids = ""
    function add(b) {
      if (!b || !b.id || out.length >= 8)
        return
      if (ids.indexOf("|" + b.id + "|") >= 0)
        return
      ids += "|" + b.id + "|"
      out.push(b)
    }
    for (var i = 0; i < bots.length; i++) {
      var b = bots[i]
      if (b && (b.waiting || Number(b.unread || 0) > 0 || b.busy))
        add(b)
    }
    for (var j = 0; j < bots.length; j++)
      add(bots[j])
    return out
  }
  readonly property bool lively: unreadCount > 0 || waitingCount > 0

  property string _inboxOutput: ""
  property string _inboxError: ""

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

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("inbox.py").toString().replace(/^file:\/\//, ""))
  }

  function capPath() {
    return decodeURIComponent(Qt.resolvedUrl("bin/run-capped").toString().replace(/^file:\/\//, ""))
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
    s = String(s || "squircle").toLowerCase()
    var ok = {
      "tablet": 1, "squircle": 1, "circle": 1, "hex": 1, "hexagon": 1,
      "capsule": 1, "pill": 1, "cloud": 1, "teardrop": 1, "blob": 1,
      "egg": 1, "group": 1, "square": 1, "pentagon": 1, "wedge": 1,
      "pebble": 1, "bean": 1, "gem": 1, "crystal": 1, "shield": 1,
      "dome": 1, "arch": 1, "leaf": 1, "cylinder": 1
    }
    if (ok[s])
      return s === "hexagon" ? "hex" : (s === "square" ? "squircle" : s)
    return "squircle"
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
        feed: root.clip(b.feed, 200),
        messages: root.sanitizeMessages(b.messages),
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

  function sanitizeMessages(arr) {
    var out = []
    if (!arr || arr.length === undefined)
      return out
    var n = Math.min(arr.length, 8)
    for (var i = 0; i < n; i++) {
      var m = arr[i]
      if (!m || typeof m !== "object")
        continue
      var text = root.clip(m.text, 160)
      if (text === "" && m.streaming !== true)
        continue
      var role = String(m.role || "") === "assistant" ? "assistant" : "user"
      out.push({
        id: root.allowIdent(m.id, 40) || ("m" + i),
        role: role,
        text: text,
        streaming: m.streaming === true
      })
    }
    return out
  }

  function botById(id) {
    id = String(id || "")
    if (id === "")
      return null
    for (var i = 0; i < root.bots.length; i++) {
      if (String(root.bots[i].id) === id)
        return root.bots[i]
    }
    return null
  }

  function pickChatBot() {
    var focused = root.botById(root.focusedId)
    if (focused)
      return focused
    var liveBot = null
    for (var i = 0; i < root.bots.length; i++) {
      if (root.bots[i].busy) { liveBot = root.bots[i]; break }
    }
    if (!liveBot) {
      for (var j = 0; j < root.bots.length; j++) {
        if (root.bots[j].waiting) { liveBot = root.bots[j]; break }
      }
    }
    if (!liveBot) {
      for (var u = 0; u < root.bots.length; u++) {
        if (Number(root.bots[u].unread || 0) > 0) { liveBot = root.bots[u]; break }
      }
    }
    if (!liveBot && root.bots.length > 0)
      liveBot = root.bots[0]
    return liveBot
  }

  function focusBot(bot) {
    if (!bot || !bot.id)
      return
    root.focusedId = String(bot.id)
    root.focusedName = String(bot.name || "Bot")
    root.syncChat(bot)
    root.stamp = root.stamp + 1
  }

  function syncChat(bot) {
    var msgs = (bot && bot.messages) ? bot.messages : []
    var name = bot && bot.name ? bot.name : ""
    var shape = bot && bot.shape ? bot.shape : "squircle"
    var color = bot && bot.color ? bot.color : "#888888"
    var same = chatList.count === msgs.length
    if (same) {
      for (var i = 0; i < msgs.length; i++) {
        if (String(chatList.get(i).msgId) !== String(msgs[i].id)) {
          same = false
          break
        }
      }
    }
    if (!same) {
      chatList.clear()
      for (var j = 0; j < msgs.length; j++) {
        chatList.append({
          msgId: msgs[j].id,
          role: msgs[j].role,
          line: msgs[j].text,
          streaming: msgs[j].streaming === true,
          botName: name,
          faceShape: shape,
          faceColor: color
        })
      }
      return
    }
    for (var k = 0; k < msgs.length; k++) {
      chatList.setProperty(k, "line", msgs[k].text)
      chatList.setProperty(k, "streaming", msgs[k].streaming === true)
      chatList.setProperty(k, "botName", name)
      chatList.setProperty(k, "faceShape", shape)
      chatList.setProperty(k, "faceColor", color)
    }
  }

  function applyInbox(text, fromDemo) {
    root.refreshing = false
    if (String(text || "").length > root.maxInboxBytes) {
      root.lastError = "inbox snapshot too large"
      root.hasSnapshot = false
      root.bots = []
      root.syncModel([])
      root.stamp = root.stamp + 1
      root.demo = false
      return
    }
    try {
      var data = JSON.parse(text)
      if (!data || data.ok !== true || data.client !== "glorics.grok-bots") {
        root.lastError = root.clip(data && data.error ? data.error : "Could not read inbox", 80)
        root.hasSnapshot = false
        root.bots = []
        root.syncModel([])
        root.stamp = root.stamp + 1
        root.demo = false
        return
      }
      root.bots = root.sanitizeBots(data.bots)
      root.syncModel(root.bots)
      root.stamp = root.stamp + 1
      var liveBot = root.pickChatBot()
      if (root.focusedId !== "" && !root.botById(root.focusedId))
        root.focusedId = liveBot ? String(liveBot.id || "") : ""
      if (liveBot) {
        if (root.focusedId === "")
          root.focusedId = String(liveBot.id || "")
        root.focusedName = String(liveBot.name || "Bot")
      } else {
        root.focusedName = ""
      }
      root.syncChat(liveBot)
      root.demo = fromDemo === true || data.demo === true
      root.hasSnapshot = true
      root.lastError = root.clip(data.error || "", 80)
      var nextPath = String(data.sourcePath || "")
      if (nextPath.indexOf("/home/") === 0 && nextPath.indexOf("..") < 0)
        root.sourcePath = nextPath
      else if (nextPath === "")
        root.sourcePath = ""
    } catch (e) {
      root.lastError = "Could not read inbox"
      root.hasSnapshot = false
      root.bots = []
      root.syncModel([])
      root.stamp = root.stamp + 1
      root.demo = false
    }
  }

  function syncModel(arr) {
    var keys = ["id", "name", "team", "preview", "feed", "when", "unread", "waiting", "busy", "activity", "shape", "color"]
    while (botList.count > arr.length)
      botList.remove(botList.count - 1)
    for (var i = 0; i < arr.length; i++) {
      var b = arr[i]
      if (i >= botList.count) {
        botList.append(b)
        continue
      }
      for (var k = 0; k < keys.length; k++) {
        var key = keys[k]
        var val = b[key]
        if (val === undefined)
          val = (key === "unread" ? 0 : ((key === "waiting" || key === "busy") ? false : ""))
        botList.setProperty(i, key, val)
      }
    }
  }

  function refresh() {
    if (root.live && watchProc.running)
      return
    if (inboxProcess.running) {
      root._pending = true
      return
    }
    root.refreshing = true
    root._inboxOutput = ""
    root._inboxError = ""
    inboxProcess.command = ["bash", capPath(), "python3", helperPath()]
    inboxProcess.running = true
  }

  Process {
    id: inboxProcess
    running: false
    command: []
    stdout: StdioCollector { id: inboxStdout; waitForEnd: true; onStreamFinished: root._inboxOutput = text }
    stderr: StdioCollector { id: inboxStderr; waitForEnd: true; onStreamFinished: root._inboxError = text }
    onExited: function(exitCode) {
      var stdout = String(inboxStdout.text || root._inboxOutput || "")
      var stderr = String(inboxStderr.text || root._inboxError || "")
      if (exitCode === 0 && stdout.trim() !== "") {
        root.applyInbox(stdout, false)
      } else {
        root.refreshing = false
        root.lastError = root.clip(stderr || "Could not read Grok Bot roster", 80)
        root.hasSnapshot = false
        root.bots = []
        root.syncModel([])
        root.stamp = root.stamp + 1
        root.demo = false
      }
      if (root._pending && !root.live) {
        root._pending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: watchProc
    running: root.live
    command: ["python3", root.helperPath(), "--watch"]
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line || "").trim()
        if (s !== "")
          root.applyInbox(s, false)
      }
    }
  }

  FileView {
    id: sourceFile
    path: root.sourcePath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Timer {
    interval: root.live ? 250 : 3000
    running: !watchProc.running
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
