import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// Tunnel throughput: two rates, a 60-second sparkline, session totals.
//
// One ink, like the rest of the panel: everything is drawn from the theme
// foreground. Download is a filled area with a solid line, upload a dashed
// line, told apart by mark, never by hue, so it reads the same on every
// theme and for colour-blind eyes. The rate row doubles as the legend, with
// a miniature of each mark beside its number.
Item {
  id: root

  // Newest sample last; bytes per second.
  property var rxHistory: []
  property var txHistory: []
  property real rxRate: 0
  property real txRate: 0
  property real sessionRx: 0
  property real sessionTx: 0
  property int uptimeSec: 0

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  readonly property int samples: 60
  readonly property real chartHeight: Style.space(36)

  // Hovered sample index (0 = oldest), or -1.
  property int hoverIndex: -1

  implicitHeight: column.implicitHeight
  implicitWidth: parent ? parent.width : Style.space(300)

  function fmtRate(bps) {
    var v = Number(bps) || 0
    if (v < 1024) return Math.round(v) + " B/s"
    if (v < 1024 * 1024) return (v / 1024).toFixed(v < 10240 ? 1 : 0) + " KB/s"
    return (v / (1024 * 1024)).toFixed(v < 10485760 ? 2 : 1) + " MB/s"
  }

  function fmtBytes(b) {
    var v = Number(b) || 0
    if (v < 1024) return Math.round(v) + " B"
    if (v < 1024 * 1024) return (v / 1024).toFixed(0) + " KB"
    if (v < 1024 * 1024 * 1024) return (v / (1024 * 1024)).toFixed(1) + " MB"
    return (v / (1024 * 1024 * 1024)).toFixed(2) + " GB"
  }

  function fmtUptime(s) {
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
    if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
    if (m > 0) return m + "m " + ((s % 60) < 10 ? "0" : "") + (s % 60) + "s"
    return s + "s"
  }

  // Both series share one y-scale (one axis, always).
  readonly property real yMax: {
    var m = 1024
    for (var i = 0; i < rxHistory.length; i++) if (rxHistory[i] > m) m = rxHistory[i]
    for (var j = 0; j < txHistory.length; j++) if (txHistory[j] > m) m = txHistory[j]
    return m
  }

  function xAt(i, n, w) { return n <= 1 ? w : i / (n - 1) * w }
  function yAt(v, h) { return h - Math.max(0, Math.min(1, v / yMax)) * (h - 3) - 1.5 }

  // "M x y L x y …" for a series, right-aligned so the newest sample sits at
  // the right edge and the line grows in from the right as samples arrive.
  function linePath(series, w, h) {
    var n = series.length
    if (n === 0) return ""
    var d = ""
    for (var i = 0; i < n; i++) {
      var x = xAt(root.samples - n + i, root.samples, w)
      d += (i === 0 ? "M" : "L") + x.toFixed(1) + " " + yAt(series[i], h).toFixed(1)
    }
    return d
  }

  function areaPath(series, w, h) {
    var n = series.length
    if (n === 0) return ""
    var x0 = xAt(root.samples - n, root.samples, w)
    return "M" + x0.toFixed(1) + " " + h + linePath(series, w, h).substring(1).replace(/^([0-9.]+ [0-9.]+)/, "L$1") + "L" + w + " " + h + "Z"
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(6)

    // Rates, also the legend: each number sits beside its own mark.
    Row {
      width: parent.width
      spacing: Style.space(16)

      Row {
        spacing: Style.space(6)
        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(14); height: Style.space(10)
          Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
              strokeColor: "transparent"; strokeWidth: 0
              PathSvg { path: "M0 10 L0 7 Q3.5 6 5.5 3 Q7.5 0 9.5 4 Q11.5 8 14 5 L14 10 Z" }
            }
            ShapePath {
              fillColor: "transparent"
              strokeColor: root.foreground; strokeWidth: 1.6
              capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
              PathSvg { path: "M0 7 Q3.5 6 5.5 3 Q7.5 0 9.5 4 Q11.5 8 14 5" }
            }
          }
        }
        Text {
          text: "↓ " + root.fmtRate(root.rxRate)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Row {
        spacing: Style.space(6)
        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(12); height: Style.space(10)
          Row {
            anchors.centerIn: parent
            spacing: 2
            Repeater { model: 3; Rectangle { width: 2.5; height: 2; color: root.foreground } }
          }
        }
        Text {
          text: "↑ " + root.fmtRate(root.txRate)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    // Sparkline
    Item {
      id: chart
      width: parent.width
      height: root.chartHeight

      // Recessive baseline
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width; height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
      }

      Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        // Download: filled area + 2px line
        ShapePath {
          fillColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
          strokeColor: "transparent"
          strokeWidth: 0
          PathSvg { path: root.areaPath(root.rxHistory, chart.width, chart.height) }
        }
        ShapePath {
          fillColor: "transparent"
          strokeColor: root.foreground
          strokeWidth: 2
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathSvg { path: root.linePath(root.rxHistory, chart.width, chart.height) }
        }
        // Upload: dashed 2px line, foreground
        ShapePath {
          fillColor: "transparent"
          strokeColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
          strokeWidth: 2
          strokeStyle: ShapePath.DashLine
          dashPattern: [2.5, 2]
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathSvg { path: root.linePath(root.txHistory, chart.width, chart.height) }
        }
      }

      // Hover: crosshair at the nearest sample, values in a small label.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
          var n = root.rxHistory.length
          if (n === 0) { root.hoverIndex = -1; return }
          var slot = Math.round(mouse.x / Math.max(1, chart.width) * (root.samples - 1))
          var i = slot - (root.samples - n)
          root.hoverIndex = i >= 0 && i < n ? i : -1
        }
        onExited: root.hoverIndex = -1
      }

      Rectangle {
        visible: root.hoverIndex >= 0
        width: 1; height: parent.height
        x: root.xAt(root.samples - root.rxHistory.length + root.hoverIndex, root.samples, chart.width)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
      }
    }

    // Hover readout when present, session totals otherwise, same slot, so
    // nothing jumps.
    Text {
      width: parent.width
      text: {
        if (root.hoverIndex >= 0) {
          var ago = root.rxHistory.length - 1 - root.hoverIndex
          return (ago === 0 ? "now" : ago + " s ago") + "   ↓ " + root.fmtRate(root.rxHistory[root.hoverIndex])
                 + "   ↑ " + root.fmtRate(root.txHistory[root.hoverIndex] || 0)
        }
        return "Session  ↓ " + root.fmtBytes(root.sessionRx) + "   ↑ " + root.fmtBytes(root.sessionTx)
               + "   ·  up " + root.fmtUptime(root.uptimeSec)
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
