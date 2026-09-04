import QtQuick
import QtQuick.Shapes
import qs.Commons

// Colored geometric bot face used in the bar cluster and roster rows.
Item {
  id: root

  property real iconSize: Style.space(22)
  property color color: "#e23d3d"
  property string shape: "square"
  property bool lively: false
  property color holeColor: Color.background

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  readonly property real s: width
  readonly property real eyeW: Math.max(2, s * 0.12)
  readonly property real eyeH: Math.max(2, s * 0.22)
  readonly property real eyeY: s * 0.38
  property real bob: 0

  SequentialAnimation on bob {
    running: root.lively
    loops: Animation.Infinite
    NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
    NumberAnimation { to: -1.0; duration: 420; easing.type: Easing.InOutSine }
  }

  Shape {
    id: body
    anchors.centerIn: parent
    anchors.verticalCenterOffset: root.bob
    width: root.s
    height: root.s
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      PathSvg { path: root.bodyPath() }
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: root.eyeY + root.bob
    spacing: Math.max(2, root.s * 0.16)

    Repeater {
      model: 2
      Rectangle {
        width: root.eyeW
        height: root.eyeH
        radius: width / 2
        color: root.holeColor
      }
    }
  }

  function bodyPath() {
    var kind = String(root.shape || "square").toLowerCase()
    if (kind === "circle")
      return circlePath()
    if (kind === "hexagon")
      return polygonPath(6, 0)
    if (kind === "pentagon")
      return polygonPath(5, -Math.PI / 2)
    if (kind === "blob")
      return blobPath()
    return roundedSquarePath()
  }

  function roundedSquarePath() {
    var r = root.s * 0.22
    var x0 = root.s * 0.06
    var y0 = root.s * 0.06
    var x1 = root.s * 0.94
    var y1 = root.s * 0.94
    return "M" + (x0 + r) + " " + y0
      + " H" + (x1 - r)
      + " Q" + x1 + " " + y0 + " " + x1 + " " + (y0 + r)
      + " V" + (y1 - r)
      + " Q" + x1 + " " + y1 + " " + (x1 - r) + " " + y1
      + " H" + (x0 + r)
      + " Q" + x0 + " " + y1 + " " + x0 + " " + (y1 - r)
      + " V" + (y0 + r)
      + " Q" + x0 + " " + y0 + " " + (x0 + r) + " " + y0
      + " Z"
  }

  function circlePath() {
    var cx = root.s / 2
    var cy = root.s / 2
    var r = root.s * 0.46
    return "M" + (cx + r) + " " + cy
      + " A" + r + " " + r + " 0 1 1 " + (cx - r) + " " + cy
      + " A" + r + " " + r + " 0 1 1 " + (cx + r) + " " + cy
      + " Z"
  }

  function polygonPath(sides, rot) {
    var cx = root.s / 2
    var cy = root.s / 2
    var r = root.s * 0.46
    var d = ""
    for (var i = 0; i < sides; i++) {
      var a = rot + (Math.PI * 2 * i) / sides
      var x = cx + r * Math.cos(a)
      var y = cy + r * Math.sin(a)
      d += (i === 0 ? "M" : "L") + x.toFixed(2) + " " + y.toFixed(2) + " "
    }
    return d + "Z"
  }

  function blobPath() {
    var s = root.s
    return "M" + (s * 0.22) + " " + (s * 0.30)
      + " C" + (s * 0.08) + " " + (s * 0.08) + " " + (s * 0.72) + " " + (s * 0.02) + " " + (s * 0.78) + " " + (s * 0.28)
      + " C" + (s * 0.98) + " " + (s * 0.38) + " " + (s * 0.96) + " " + (s * 0.78) + " " + (s * 0.70) + " " + (s * 0.88)
      + " C" + (s * 0.42) + " " + (s * 1.00) + " " + (s * 0.06) + " " + (s * 0.78) + " " + (s * 0.12) + " " + (s * 0.50)
      + " C" + (s * 0.14) + " " + (s * 0.40) + " " + (s * 0.18) + " " + (s * 0.36) + " " + (s * 0.22) + " " + (s * 0.30)
      + " Z"
  }
}
