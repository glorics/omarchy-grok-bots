import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool crashed: false
  property bool updateAvailable: false
  property bool newerKnown: false
  property bool canSelfUpdate: false
  property bool refreshing: false
  property bool updating: false
  property string source: "none"
  property string sourceLabel: "Checking…"
  property string statusText: "Checking…"
  property string pluginVersion: ""
  property string appVersion: ""
  property string installedVersion: ""
  property string latestVersion: ""
  property string packageVersion: ""
  property string launcher: ""
  property string appImage: ""
  property string launchCommand: ""
  property string focusPattern: "grok-bot"
  property string githubUrl: "https://github.com/glorics/omarchy-grok-bots"
  property string releasesUrl: "https://x.ai/bot"
  property string productUrl: "https://x.ai/bot"
  property string computerLabel: "Always on"
  property bool signedIn: false
  property string signedInLabel: "No"
  property string lastCheckText: ""
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 3600)
  readonly property bool busy: statusProcess.running || updateProcess.running
  readonly property bool alarming: crashed || updateAvailable

  property string _statusOutput: ""
  property string _statusError: ""
  property string _updateOutput: ""
  property string _updateError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("status.py").toString().replace(/^file:\/\//, ""))
  }

  function capPath() {
    return decodeURIComponent(Qt.resolvedUrl("bin/run-capped").toString().replace(/^file:\/\//, ""))
  }

  function capped(argv) {
    return ["bash", capPath()].concat(argv)
  }

  function clip(value, n) {
    var s = String(value || "")
    n = n || 160
    return s.length > n ? s.substring(0, n) : s
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  function refresh(fetch) {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    var command = ["python3", helperPath()]
    if (fetch) command.push("--fetch")
    statusProcess.command = capped(command)
    statusProcess.running = true
  }

  function checkForUpdates() {
    actionStatus = "Checking Cursor CDN…"
    refresh(true)
  }

  function flash(text) {
    actionStatus = clip(text, 64)
    actionStatusTimer.restart()
  }

  function applyStatus(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      lastError = "Could not read Grok Bot status"
      return
    }
    installed = data.installed === true
    running = data.running === true
    crashed = data.crashed === true
    updateAvailable = data.updateAvailable === true
    newerKnown = data.newerKnown === true
    canSelfUpdate = data.canSelfUpdate === true
    source = clip(data.source || "none", 24)
    sourceLabel = clip(data.sourceLabel || "", 64)
    statusText = clip(data.statusText || "", 64)
    pluginVersion = clip(data.pluginVersion || "", 32)
    appVersion = clip(data.appVersion || "", 32)
    installedVersion = clip(data.installedVersion || "", 32)
    latestVersion = clip(data.latestVersion || "", 32)
    packageVersion = clip(data.packageVersion || "", 32)
    launcher = String(data.launcher || "")
    appImage = String(data.appImage || "")
    launchCommand = String(data.launchCommand || "")
    focusPattern = String(data.focusPattern || "grok-bot")
    githubUrl = String(data.githubUrl || githubUrl)
    releasesUrl = String(data.releasesUrl || releasesUrl)
    productUrl = String(data.productUrl || productUrl)
    computerLabel = clip(data.computerLabel || "Always on", 32)
    signedIn = data.signedIn === true
    signedInLabel = clip(data.signedInLabel || (signedIn ? "Yes" : "No"), 16)
    lastCheckText = clip(data.lastCheckText || "", 24)
    lastError = ""
  }

  function launch() {
    if (!installed || !launchCommand) {
      openReleases()
      return
    }
    Quickshell.execDetached(["omarchy-launch-or-focus", focusPattern, launchCommand])
    actionStatus = running ? "Focusing Grok Bot" : "Launching Grok Bot"
    actionStatusTimer.restart()
    delayedRefresh.restart()
  }

  function updateNow() {
    if (updateProcess.running) return
    if (!canSelfUpdate) {
      checkForUpdates()
      return
    }
    _updateOutput = ""
    _updateError = ""
    updating = true
    actionStatus = "Downloading Linux AppImage…"
    updateProcess.command = capped(["--max-seconds", "330", "python3", helperPath(), "--update"])
    updateProcess.running = true
  }

  function openGitHub() {
    Quickshell.execDetached(["omarchy-launch-browser", githubUrl])
  }

  function openProduct() {
    Quickshell.execDetached(["omarchy-launch-browser", productUrl])
  }

  function openReleases() {
    Quickshell.execDetached(["omarchy-launch-browser", releasesUrl || productUrl])
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Timer {
    id: delayedRefresh
    interval: 1200
    repeat: false
    onTriggered: root.refresh(false)
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: if (!root.updating) root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0 && stdout.trim() !== "") {
        root.applyStatus(stdout)
        if (root.actionStatus === "Checking Cursor CDN…") {
          if (root.updateAvailable)
            root.actionStatus = "Update available · " + root.latestVersion
          else if (root.latestVersion !== "")
            root.actionStatus = "Up to date · " + root.latestVersion
          else
            root.actionStatus = "Could not read the Cursor feed"
          actionStatusTimer.restart()
        }
      } else {
        root.lastError = root.elideStatus(stderr || stdout || "Could not read Grok Bot status")
      }
    }
  }

  Process {
    id: updateProcess
    running: false
    command: []
    stdout: StdioCollector { id: updateStdout; waitForEnd: true; onStreamFinished: root._updateOutput = text }
    stderr: StdioCollector { id: updateStderr; waitForEnd: true; onStreamFinished: root._updateError = text }
    onExited: function(exitCode) {
      root.updating = false
      var stdout = String(updateStdout.text || root._updateOutput || "").trim()
      var stderr = String(updateStderr.text || root._updateError || "").trim()
      if (exitCode === 0) {
        root.lastError = ""
        root.actionStatus = stdout !== "" ? stdout : "Updated"
      } else {
        root.lastError = root.elideStatus(stderr || stdout || "Update failed")
        root.actionStatus = root.lastError
      }
      actionStatusTimer.restart()
      root.refresh(false)
    }
  }
}
