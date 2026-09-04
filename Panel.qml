import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "glorics.grok-bots"
  ipcTarget: "glorics.grok-bots"
  manageIpc: false

  property int actionIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0
  property int selectedBot: 0
  readonly property var livePhrases: [
    "Cloud computer",
    "Remote control",
    "AI teammates",
    "Always on",
    "Their computer",
    "Shared computer"
  ]
  readonly property var idlePhrases: [
    "Still on",
    "Bots keep going",
    "Computer's up"
  ]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: grok.crashed || grok.updateAvailable ? urgent : foreground
  readonly property color barIconColor: grok.alarming ? (bar ? bar.urgent : urgent) : (bar ? bar.barForeground : foreground)
  readonly property color holeColor: bar ? (bar.background || Color.bar.background) : Color.background
  readonly property int rowH: Style.space(58)
  readonly property var actions: buildActions()
  readonly property var selectedAction: actions.length > 0 ? actions[Math.max(0, Math.min(actionIndex, actions.length - 1))] : null

  function buildActions() {
    var rows = []
    if (grok.installed) {
      rows.push({
        id: "open",
        label: grok.running ? "Focus Grok Bot" : "Open Grok Bot",
        hint: "Enter",
        run: function() { grok.launch(); root.close() }
      })
    } else {
      rows.push({
        id: "install",
        label: "Get Grok Bot",
        hint: "Enter",
        run: function() { grok.openProduct(); root.close() }
      })
    }
    rows.push({
      id: "check",
      label: grok.refreshing && grok.actionStatus.indexOf("Checking") === 0
        ? "Checking…"
        : "Check for updates",
      hint: "U",
      run: function() { grok.checkForUpdates() }
    })
    if (grok.canSelfUpdate && grok.updateAvailable) {
      rows.push({
        id: "update",
        label: grok.updating ? "Updating…" : "Update now",
        hint: "Shift+U",
        run: function() { grok.updateNow() }
      })
    }
    rows.push({
      id: "product",
      label: "Open x.ai/bot",
      hint: "G",
      run: function() { grok.openProduct(); root.close() }
    })
    return rows
  }

  function selectAction(index) {
    if (actions.length === 0) return
    var wrapped = ((index % actions.length) + actions.length) % actions.length
    actionIndex = wrapped
  }

  function activateCursor() {
    if (inbox.bots.length > 0 && selectedBot >= 0 && selectedBot < inbox.bots.length) {
      openBot(inbox.bots[selectedBot])
      return
    }
    if (!selectedAction) return
    selectedAction.run()
  }

  function phraseList() {
    if (grok.running) return livePhrases
    if (grok.installed && !grok.crashed) return idlePhrases
    return []
  }

  function heroMeta() {
    if (grok.updating) return "Updating"
    if (grok.crashed) return "Client crashed"
    if (grok.updateAvailable) return "Update available"
    if (inbox.demo) return "demo roster"
    var phrases = phraseList()
    if (phrases.length > 0)
      return phrases[phraseIndex % phrases.length]
    return "Not installed"
  }

  function heroDetail() {
    var parts = []
    parts.push(inbox.botCount + " bots")
    parts.push(inbox.waitingCount + " waiting on you")
    parts.push(inbox.unreadBots + " unread")
    return parts.join(" · ")
  }

  function openBot(bot) {
    grok.launch()
    root.close()
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) grok.launch()
    else if (button === Qt.MiddleButton) grok.checkForUpdates()
    else openTimer.restart()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    actionIndex = 0
    phraseIndex = 0
    selectedBot = 0
    if (panelFlick) panelFlick.contentY = 0
    grok.refresh(false)
    inbox.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onActionsChanged: if (actionIndex >= actions.length) actionIndex = Math.max(0, actions.length - 1)

  Service {
    id: grok
    settings: root.settings
    githubUrl: ""
    onRunningChanged: root.phraseIndex = 0
  }

  Inbox {
    id: inbox
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { grok.refresh(false); inbox.refresh(); return "ok" }
    function launch(): string { grok.launch(); return "ok" }
    function update(): string { grok.updateNow(); return "ok" }
    function status(): string { return grok.statusText }
  }

  Timer {
    id: openTimer
    interval: 40
    repeat: false
    onTriggered: root.toggle()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    pressable: true
    interactive: true
    tooltipText: "Grok Bot"
    active: grok.alarming || inbox.unreadBots > 0
    fixedWidth: Math.max(Style.bar.iconSlot, cluster.implicitWidth + Style.space(10))
    onPressed: function(buttonCode) { root.triggerPress(buttonCode) }

    Row {
      id: cluster
      anchors.centerIn: parent
      spacing: Style.space(4)
      height: Style.space(22)

      Item {
        width: Style.space(18)
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter

        GrokBotIcon {
          anchors.centerIn: parent
          iconSize: Style.space(16)
          color: root.barIconColor
          running: grok.running || inbox.lively
          alarming: grok.alarming || inbox.unreadBots > 0
          installed: grok.installed || inbox.hasSnapshot
          opacity: grok.installed || inbox.hasSnapshot ? 1.0 : 0.55
        }

        CountBubble {
          count: inbox.unreadCount
          fill: root.urgent
          ink: Color.background
          fontFamily: root.fontFamily
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(6)
          anchors.topMargin: -Style.space(8)
        }
      }

      Repeater {
        model: inbox.attentionBots
        Item {
          required property var modelData
          width: Style.space(16)
          height: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter

          BotFace {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            iconSize: Style.space(16)
            color: modelData.color
            shape: modelData.shape
            lively: modelData.waiting || Number(modelData.unread || 0) > 0
            holeColor: root.holeColor
          }

          CountBubble {
            count: Number(modelData.unread || 0)
            fill: root.urgent
            ink: Color.background
            fontFamily: root.fontFamily
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -Style.space(8)
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        if (dy !== 0) {
          if (inbox.bots.length > 0) {
            var n = inbox.bots.length
            root.selectedBot = ((root.selectedBot + dy) % n + n) % n
          } else {
            root.selectAction(root.actionIndex + dy)
          }
        }
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { grok.refresh(false); inbox.refresh() }
        else if (t === "u") grok.checkForUpdates()
        else if (t === "U") grok.updateNow()
        else if (t === "g" || t === "G") { grok.openProduct(); root.close() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Grok Bot"
            meta: root.heroMeta()
            detail: root.heroDetail()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: grok.installed || inbox.hasSnapshot ? 1.0 : 0.55
            iconComponent: Component {
              GrokBotIcon {
                iconSize: Style.space(42)
                color: root.iconColor
                running: grok.running || inbox.lively
                alarming: grok.alarming || inbox.unreadBots > 0
                installed: grok.installed || inbox.hasSnapshot
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh (R)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: { grok.refresh(false); inbox.refresh() }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: grok.actionStatus !== "" || grok.lastError !== "" || inbox.lastError !== ""
            width: parent.width
            text: grok.actionStatus !== "" ? grok.actionStatus : (grok.lastError !== "" ? grok.lastError : inbox.lastError)
            color: (grok.lastError !== "" || inbox.lastError !== "") && grok.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          BorderSurface {
            visible: grok.crashed || !grok.installed || grok.updateAvailable
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              textFormat: Text.PlainText
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: grok.crashed
                ? "The last session ended unexpectedly. Open Grok Bot to start a new one."
                : (!grok.installed
                  ? "Install the Grok Bot Linux AppImage, then this widget can launch it."
                  : ("Grok Bot " + grok.latestVersion + " is on the Cursor CDN."))
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: inbox.demo
              ? "GROK BOT · demo roster"
              : (inbox.botCount > 0 ? "GROK BOT · inbox" : "GROK BOT")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.6
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.heroDetail()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            width: parent.width
            spacing: 0
            visible: inbox.bots.length > 0

            Repeater {
              model: inbox.bots

              Item {
                id: row
                required property var modelData
                required property int index
                width: parent.width
                height: root.rowH

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: row.index === 0 || (root.cursorActive && root.selectedBot === row.index)
                    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    : "transparent"
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursorActive = true
                    root.selectedBot = row.index
                  }
                  onClicked: root.openBot(row.modelData)
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)

                  BotFace {
                    Layout.preferredWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                    iconSize: Style.space(28)
                    color: row.modelData.color
                    shape: row.modelData.shape
                    lively: row.modelData.waiting === true
                    holeColor: root.holeColor
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                      width: parent.width
                      spacing: Style.space(6)
                      Text {
                        textFormat: Text.PlainText
                        text: String(row.modelData.name || "Bot")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }
                      Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: String(row.modelData.team || "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: String(row.modelData.when || "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: row.modelData.busy
                        ? String(row.modelData.activity || "Working")
                        : String(row.modelData.preview || "No messages yet")
                      color: row.modelData.waiting ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  CountBubble {
                    visible: Number(row.modelData.unread || 0) > 0
                    count: Number(row.modelData.unread || 0)
                    fill: root.urgent
                    ink: Color.background
                    fontFamily: root.fontFamily
                    tail: false
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                  }
                }
              }
            }
          }

          Text {
            visible: inbox.bots.length === 0
            width: parent.width
            padding: Style.space(18)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            text: inbox.lastError !== ""
              ? inbox.lastError
              : (grok.installed
                ? "No bots yet. Open Grok Bot and sign in. This widget reads the client's local roster."
                : "Install the Grok Bot Linux AppImage, then this widget can show your bots.")
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: "Status"; value: grok.statusText }
            InfoPair { label: "Computer"; value: grok.computerLabel }
            InfoPair { label: "Signed in"; value: grok.signedInLabel }
            InfoPair {
              visible: grok.appVersion !== "" || grok.installedVersion !== ""
              label: "Version"
              value: grok.appVersion || grok.installedVersion
            }
            InfoPair {
              visible: grok.latestVersion !== ""
              label: "Latest"
              value: grok.latestVersion + (grok.updateAvailable ? " · newer" : " · current")
            }
            InfoPair {
              visible: grok.lastCheckText !== ""
              label: "Checked"
              value: grok.lastCheckText
            }
            InfoPair { label: "Source"; value: grok.sourceLabel }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: actionColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.actions
              ActionRow {
                required property var modelData
                required property int index
                width: actionColumn.width
                action: modelData
                rowIndex: index
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            topPadding: Style.space(2)
            text: inbox.demo
              ? "Community plugin · demo roster · Linux AppImage"
              : "Community plugin · Linux AppImage"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 3200
    running: root.opened && grok.installed && !grok.crashed && !grok.updating && !inbox.demo
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero
      property: "metaOpacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.phraseList().length
        root.phraseIndex = n > 0 ? (root.phraseIndex + 1) % n : 0
      }
    }
    PropertyAnimation {
      target: hero
      property: "metaOpacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  component InfoPair: Item {
    property string label: ""
    property string value: ""

    width: parent.width
    implicitHeight: Style.font.bodySmall + Style.space(4)
    height: implicitHeight
    clip: true

    Text {
      textFormat: Text.PlainText
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.NoWrap
    }
    Text {
      textFormat: Text.PlainText
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.NoWrap
      maximumLineCount: 1
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property var action: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && inbox.bots.length === 0 && root.actionIndex === rowIndex
    foreground: root.foreground
    implicitHeight: actionInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.actionIndex = actionRow.rowIndex
      }
      onClicked: if (actionRow.action) actionRow.action.run()
    }

    Row {
      id: actionInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        width: parent.width - hint.implicitWidth - parent.spacing
        text: actionRow.action ? actionRow.action.label : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        id: hint
        text: actionRow.action ? actionRow.action.hint : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
