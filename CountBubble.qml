import QtQuick
import qs.Commons

// Small chat bubble with a count. Used on bar faces and inbox rows.
Item {
  id: root

  property int count: 0
  property color fill: Color.urgent
  property color ink: Color.background
  property string fontFamily: Style.font.family
  property bool tail: true

  visible: count > 0
  implicitWidth: Math.max(Style.space(14), pill.implicitWidth)
  implicitHeight: pill.implicitHeight + (tail ? Style.space(3) : 0)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: pill
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    implicitWidth: label.implicitWidth + Style.space(8)
    implicitHeight: Style.space(13)
    radius: height / 2
    color: root.fill

    Text {
      id: label
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.count > 99 ? "99" : String(root.count)
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Rectangle {
    visible: root.tail
    width: Style.space(5)
    height: Style.space(5)
    rotation: 45
    color: root.fill
    anchors.horizontalCenter: pill.horizontalCenter
    anchors.top: pill.bottom
    anchors.topMargin: -Style.space(3)
  }
}
