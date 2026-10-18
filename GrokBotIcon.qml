import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// Themed x.ai/bot IconMark face. Expression table, blink squash, and
// per-state body motion follow the public site animation. Overlay morphs
// (orbit, radar, pencil, …) stay off — they do not read at bar/panel size.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Commons.Color.foreground
  property bool running: false
  property bool alarming: false
  property bool installed: true

  property var mark: null
  property int fromId: 0
  property int toId: 0
  property real mix: 1
  property real blink: 0
  property real gaze: 0
  property real nowMs: 0
  property string mood: "humming"
  property int frameIndex: 0
  property real moodT0: 0
  property real nextFrameAt: 0
  property real nextMoodAt: 0
  property real nextBlinkAt: 0
  property real nextGazeAt: 0
  property real bodyX: 0
  property real bodyY: 0
  property real bodyRot: 0
  property real bodySy: 1

  readonly property bool awake: installed && !alarming
  readonly property real s: width / 259
  readonly property real headC: 114.2705
  readonly property color bodyColor: root.color
  readonly property color eyeColor: Commons.Color.background

  // Public face states. Stay is shorter than the site so the orb actually
  // shows the catalog instead of sitting on idle.
  readonly property var catalog: [
    { name: "humming", frames: [0, 8], hold: [2800, 5000], stay: [4500, 7000], blink: true },
    { name: "idle", frames: [0, 8], hold: [2800, 4800], stay: [4500, 7000], blink: true },
    { name: "curious", frames: [3, 21, 0, 15], hold: [1400, 2400], stay: [4000, 6000], blink: true },
    { name: "thinking", frames: [8, 16, 14, 17, 5], hold: [1600, 2800], stay: [4000, 6500], blink: true },
    { name: "listening", frames: [10, 1, 19], hold: [2200, 3800], stay: [4000, 6000], blink: true },
    { name: "searching", frames: [15, 9, 3, 20, 12, 18], hold: [800, 1400], stay: [3500, 5500], blink: true },
    { name: "working", frames: [7, 16, 11, 10], hold: [1400, 2600], stay: [4000, 6000], blink: true },
    { name: "happy", frames: [2, 11, 17, 19], hold: [1800, 3200], stay: [4000, 6000], blink: true },
    { name: "playful", frames: [2, 17, 11, 8], hold: [1200, 2400], stay: [3500, 5500], blink: true },
    { name: "surprised", frames: [3, 21], hold: [1800, 2800], stay: [2800, 4000], blink: true },
    { name: "excited", frames: [2, 17, 21, 3, 11], hold: [900, 1600], stay: [3200, 5000], blink: true },
    { name: "laughing", frames: [2, 11, 17], hold: [900, 1800], stay: [3200, 4800], blink: true },
    { name: "confused", frames: [14, 5, 8], hold: [1600, 2800], stay: [3500, 5500], blink: true },
    { name: "proud", frames: [15, 8, 2], hold: [2500, 4200], stay: [4000, 6000], blink: true },
    { name: "shy", frames: [0, 24, 13], hold: [2200, 4000], stay: [4000, 6000], blink: true },
    { name: "drowsy", frames: [4, 22, 13], hold: [3000, 5500], stay: [4500, 7000], blink: false },
    { name: "bored", frames: [4, 22, 0], hold: [2500, 4500], stay: [4000, 6500], blink: true },
    { name: "sad", frames: [4, 13, 22], hold: [3000, 5000], stay: [4000, 6000], blink: true },
    { name: "suspicious", frames: [14, 5, 23], hold: [2000, 3400], stay: [3500, 5500], blink: true },
    { name: "angry", frames: [7, 16], hold: [1800, 3000], stay: [3200, 5000], blink: true },
    { name: "scared", frames: [3, 21], hold: [800, 1500], stay: [2800, 4200], blink: true },
    { name: "celebrate", frames: [2, 8, 17], hold: [1100, 2000], stay: [3200, 4800], blink: true },
    { name: "notifying", frames: [3, 21, 0], hold: [1200, 2000], stay: [2800, 4200], blink: true }
  ]

  readonly property string headPath: mark && mark.head ? mark.head : fallbackHead
  readonly property string eye0Path: ringPath(eyeRing(0))
  readonly property string eye1Path: ringPath(eyeRing(1))

  readonly property string fallbackHead: "M228.541 114.228C228.541 130.133 225.184 145.994 218.738 160.534C212.674 174.217 203.904 186.669 193.065 196.988C155.933 232.34 99.497 238.596 55.5255 212.24C45.097 205.99 35.6851 198.072 27.7451 188.866C19.1926 178.953 12.3686 167.569 7.65781 155.351C2.60712 142.264 0 128.257 0 114.228C0 98.3219 3.35751 82.4611 9.80315 67.9215C15.8672 54.2382 24.6377 41.7862 35.4767 31.4668C72.6081 -3.88483 129.044 -10.1413 173.016 16.2153C183.444 22.4653 192.856 30.3829 200.796 39.5896C209.349 49.5018 216.173 60.8859 220.883 73.1037C225.934 86.1906 228.541 100.198 228.541 114.228Z"

  function ringPath(pts) {
    if (!pts || pts.length < 2) return ""
    var d = "M" + Number(pts[0][0]).toFixed(2) + " " + Number(pts[0][1]).toFixed(2)
    for (var i = 1; i < pts.length; i++)
      d += "L" + Number(pts[i][0]).toFixed(2) + " " + Number(pts[i][1]).toFixed(2)
    return d + "Z"
  }

  function lerpRing(a, b, t) {
    if (!a || !b) return a || b || []
    var n = Math.min(a.length, b.length)
    var out = []
    for (var i = 0; i < n; i++) {
      out.push([
        a[i][0] + (b[i][0] - a[i][0]) * t,
        a[i][1] + (b[i][1] - a[i][1]) * t
      ])
    }
    return out
  }

  function scaleRingY(pts, sy) {
    if (!pts || pts.length === 0) return pts || []
    var cx = 0, cy = 0, n = pts.length
    for (var i = 0; i < n; i++) {
      cx += pts[i][0]
      cy += pts[i][1]
    }
    cx /= n
    cy /= n
    var out = []
    for (var j = 0; j < n; j++)
      out.push([pts[j][0], cy + (pts[j][1] - cy) * sy])
    return out
  }

  function expr(frameId) {
    if (!mark || !mark.expressions) return null
    var n = Math.max(0, Math.min(mark.expressions.length - 1, frameId))
    return mark.expressions[n]
  }

  function currentRow() {
    var rows = catalog
    for (var slot = 0; slot < rows.length; slot++) {
      if (rows[slot].name === mood)
        return rows[slot]
    }
    return rows[0]
  }

  function randMs(pair) {
    return Math.round(pair[0] + Math.random() * (pair[1] - pair[0]))
  }

  function goTo(frameId) {
    if (frameId === toId && mix >= 0.99) return
    fromId = mix >= 0.5 ? toId : fromId
    toId = frameId
    mix = 0
    mixAnim.restart()
  }

  function advanceFrame() {
    var row = currentRow()
    if (!row || !row.frames || row.frames.length === 0) return
    var n = row.frames.length
    frameIndex = (frameIndex + 1 + Math.floor(Math.random() * Math.max(0, n - 1))) % n
    goTo(row.frames[frameIndex])
    nextFrameAt = nowMs + randMs(row.hold)
  }

  function pickMood() {
    var rows = catalog
    if (!rows || rows.length === 0) return
    var slot = Math.floor(Math.random() * rows.length)
    if (rows[slot].name === mood && rows.length > 1)
      slot = (slot + 1 + Math.floor(Math.random() * (rows.length - 1))) % rows.length
    mood = rows[slot].name
    frameIndex = 0
    moodT0 = nowMs
    goTo(rows[slot].frames[0])
    nextFrameAt = nowMs + randMs(rows[slot].hold)
    nextMoodAt = nowMs + randMs(rows[slot].stay)
    nextBlinkAt = nowMs + (rows[slot].blink ? 800 + Math.random() * 2200 : 1e9)
    nextGazeAt = nowMs + 400 + Math.random() * 900
  }

  function wanderGaze() {
    var row = currentRow()
    var name = row ? row.name : "idle"
    var span = 0.45
    if (name === "searching" || name === "curious" || name === "scared" || name === "playful")
      span = 0.85
    else if (name === "thinking" || name === "confused")
      span = 0.7
    else if (name === "idle" || name === "humming")
      span = 0.25
    gaze = (Math.random() * 2 - 1) * span
    var wait = 1800
    if (name === "searching") wait = 700
    else if (name === "curious" || name === "playful") wait = 1100
    nextGazeAt = nowMs + wait + Math.random() * wait
  }

  function applyBody(name, tSec) {
    var nx = 0, sx = 0, ly = 0, oy = 1
    if (name === "listening") {
      nx = 8 + 1.5 * Math.sin(0.5 * tSec)
      sx = 2
      ly = -2 + 0.8 * Math.sin(0.8 * tSec)
      oy = 1.015
    } else if (name === "thinking") {
      nx = -9 + 5 * Math.sin(0.35 * tSec)
      sx = 5 * Math.sin(0.3 * tSec)
      ly = 2.5 * Math.sin(0.6 * tSec)
    } else if (name === "searching") {
      var e = Math.sin(1.3 * tSec)
      nx = 13 * e
      sx = 7 * e
      ly = 3 * Math.sin(1.7 * tSec)
    } else if (name === "working") {
      var w = Math.sin(tSec * Math.PI * 3.2)
      nx = 4 + 2.5 * w
      sx = 3
      ly = 1.5 + 3 * Math.max(0, w)
      oy = 1 - 0.02 * Math.max(0, w)
    } else if (name === "excited") {
      var ex = (2.2 * tSec) % 1
      ly = -(10 * Math.sin(ex * Math.PI)) + 2
      oy = ex < 0.1 ? 0.92 : (ex < 0.3 ? 1.05 : 1)
      nx = 7 * Math.sin(tSec * Math.PI * 2.2)
      sx = 4 * Math.sin(1.1 * tSec)
    } else if (name === "surprised") {
      var su = Math.min(tSec / 1.2, 1)
      sx = -4 * (1 - su)
      ly = -8 * (1 - su)
      oy = tSec < 0.2 ? 1.08 : 1
      nx = 1.5 * Math.sin(11 * tSec) * (1 - su)
    } else if (name === "suspicious") {
      nx = -6 + 3 * Math.sin(0.3 * tSec)
      sx = -4 * Math.sin(0.25 * tSec)
      ly = 1 + 1.2 * Math.sin(0.45 * tSec)
    } else if (name === "angry") {
      ly = 3.5
      oy = 0.975
    } else if (name === "drowsy") {
      nx = 2.5 * Math.sin(0.32 * tSec)
      sx = 1.5 * Math.sin(0.2 * tSec)
      ly = 6 + 2.2 * Math.sin(0.36 * tSec)
      oy = 1 + 0.022 * Math.sin(0.36 * tSec)
    } else if (name === "happy") {
      var ht = Math.sin(2.4 * tSec)
      nx = 3 * Math.sin(1.2 * tSec)
      sx = 2.5 * Math.sin(1.1 * tSec)
      ly = -(3 * Math.abs(ht))
      oy = 1 + 0.02 * ht
    } else if (name === "curious") {
      nx = 10 + 6 * Math.sin(0.7 * tSec)
      sx = 5 * Math.sin(0.6 * tSec)
      ly = -2 + 1.5 * Math.sin(0.9 * tSec)
      oy = 1.01
    } else if (name === "confused") {
      var cf = Math.sin(0.8 * tSec)
      nx = 12 * cf
      sx = 3 * cf
      ly = 2 * Math.sin(0.5 * tSec)
    } else if (name === "bored") {
      nx = -3 + 4 * Math.sin(0.25 * tSec)
      sx = 4 * Math.sin(0.2 * tSec)
      ly = 5 + 1.5 * Math.sin(0.35 * tSec)
      oy = 0.99
    } else if (name === "proud") {
      nx = 2.5 * Math.sin(0.4 * tSec)
      sx = 2 * Math.sin(0.35 * tSec)
      ly = -4 + Math.sin(0.6 * tSec)
      oy = 1.03
    } else if (name === "shy") {
      nx = -8 + 3 * Math.sin(0.5 * tSec)
      sx = -3 + 2 * Math.sin(0.4 * tSec)
      ly = 3
      oy = 0.98
    } else if (name === "sad") {
      nx = 3 + 2 * Math.sin(0.3 * tSec)
      sx = 1.5 * Math.sin(0.25 * tSec)
      ly = 7 + Math.sin(0.4 * tSec)
      oy = 0.97
    } else if (name === "laughing") {
      var lh = Math.sin(tSec * Math.PI * 6.4)
      nx = 4 * lh
      sx = 2 * Math.sin(2 * tSec)
      ly = -(5 * Math.abs(lh))
      oy = 1 + 0.03 * lh
    } else if (name === "scared") {
      nx = 2 * Math.sin(0.04 * nowMs)
      sx = -2 + 1.5 * Math.sin(0.05 * nowMs)
      ly = 2 + Math.sin(1.5 * tSec)
      oy = 0.97
    } else if (name === "playful") {
      nx = 8 * Math.sin(1.4 * tSec)
      sx = 4 * Math.sin(1.1 * tSec)
      ly = -(3 * Math.abs(Math.sin(2.2 * tSec)))
      oy = 1 + 0.015 * Math.sin(2.2 * tSec)
    } else if (name === "celebrate") {
      ly = -(2.5 * Math.abs(Math.sin(1.6 * tSec)))
      oy = 1
    } else if (name === "notifying") {
      nx = 3
      sx = 2
      ly = -1
    } else {
      nx = 1.5 * Math.sin(0.5 * tSec) + 0.6 * Math.sin(0.17 * tSec)
      sx = Math.sin(0.27 * tSec)
      ly = 1.2 * Math.sin(0.85 * tSec)
      oy = 1 + 0.007 * Math.sin(0.85 * tSec)
      if (name === "humming") {
        nx = 2 * Math.sin(0.4 * tSec)
        sx = 1.5 * Math.sin(0.3 * tSec)
        ly = 1.5 * Math.sin(0.7 * tSec)
        oy = 1
      }
    }
    bodyRot = nx
    bodyX = sx
    bodyY = ly
    bodySy = oy
  }

  function eyeRing(which) {
    var a = expr(fromId)
    var b = expr(toId)
    if (!a) return []
    var look = lerpRing(a[which], b ? b[which] : a[which], Math.max(0, Math.min(1, mix)))
    if (gaze !== 0) {
      var side = expr(gaze > 0 ? 0 : 8)
      if (side)
        look = lerpRing(look, side[which], Math.min(0.5, Math.abs(gaze) * 0.42))
    }
    if (blink > 0.01)
      look = scaleRingY(look, 1 - 0.92 * blink)
    return look
  }

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  FileView {
    id: markFile
    path: decodeURIComponent(Qt.resolvedUrl("official-mark.json").toString().replace(/^file:\/\//, ""))
    printErrors: false
    onLoaded: {
      try {
        root.mark = JSON.parse(markFile.text())
        root.nowMs = Date.now()
        root.pickMood()
      } catch (e) { }
    }
  }

  NumberAnimation {
    id: mixAnim
    target: root
    property: "mix"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
  }

  SequentialAnimation {
    id: blinkAnim
    NumberAnimation { target: root; property: "blink"; to: 1; duration: 70; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 40 }
    NumberAnimation { target: root; property: "blink"; to: 0; duration: 110; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 80 }
    NumberAnimation { target: root; property: "blink"; to: 1; duration: 70; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 40 }
    NumberAnimation { target: root; property: "blink"; to: 0; duration: 110; easing.type: Easing.OutCubic }
  }

  HoverHandler {
    id: hover
    enabled: root.awake
    onHoveredChanged: if (!hovered) root.gaze = 0
  }

  Timer {
    interval: 33
    running: root.awake && root.mark
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      root.applyBody(root.mood, (root.nowMs - root.moodT0) / 1000)
      if (root.nowMs >= root.nextFrameAt)
        root.advanceFrame()
      if (root.nowMs >= root.nextMoodAt)
        root.pickMood()
      if (root.nowMs >= root.nextBlinkAt) {
        blinkAnim.restart()
        var row = root.currentRow()
        root.nextBlinkAt = root.nowMs + (row && row.blink ? 2800 + Math.random() * 4200 : 1e9)
      }
      if (hover.hovered && root.width > 1) {
        var nx = hover.point.position.x / root.width
        root.gaze = Math.max(-1, Math.min(1, (nx - 0.5) * 1.6))
      } else if (root.nowMs >= root.nextGazeAt) {
        root.wanderGaze()
      }
    }
  }

  Item {
    anchors.fill: parent
    transform: Scale {
      xScale: -1
      origin.x: root.width / 2
    }

    Shape {
      id: markShape
      width: 259
      height: 259
      x: 15 * root.s
      y: 15 * root.s
      preferredRendererType: Shape.CurveRenderer
      antialiasing: true
      transform: [
        Translate { x: -root.headC; y: -root.headC },
        Scale { yScale: root.bodySy },
        Rotation { angle: root.bodyRot },
        Translate { x: root.headC + root.bodyX; y: root.headC + root.bodyY },
        Scale { xScale: root.s; yScale: root.s }
      ]

      ShapePath {
        fillColor: root.bodyColor
        strokeWidth: 0
        PathSvg { path: root.headPath }
      }
      ShapePath {
        fillColor: root.eyeColor
        strokeWidth: 0
        PathSvg { path: root.eye0Path }
      }
      ShapePath {
        fillColor: root.eyeColor
        strokeWidth: 0
        PathSvg { path: root.eye1Path }
      }
    }
  }
}
