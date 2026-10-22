import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import "World.js" as World

// Where in the world you are, and where else you could be.
//
// Land is a single bundled SVG path (World.js, Natural Earth, public domain)
// drawn from the theme foreground at low alpha; every Proton city is a dim dot;
// the connected city is a bright dot with a slow pulse. Hover a dot for its
// name, click it to open that country's city list. Everything here is local,
// no tiles, no geocoding, no requests.
//
// The map deliberately does not draw *your* location or a line to the server:
// finding it would take a geo-IP lookup, which this plugin promises never to
// make. Lighting the exit city is the honest version. A Secure Core route is
// different: both ends are Proton servers named in the server list, so the
// map draws the hop from the entry country to the exit city.
Item {
  id: root

  property var cities: []
  // {code, city, lat, lon} for the connected server, or null.
  property var current: null
  property bool connected: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  // {code, city, lat, lon} for the Secure Core entry country, or null.
  readonly property var entry: connected && current && current.entry && current.entry.lat !== undefined && current.entry.lat !== null ? current.entry : null

  signal cityClicked(var city)

  property var hovered: null

  implicitHeight: Math.round(width * World.HEIGHT / World.WIDTH)
  readonly property real sx: width / World.WIDTH
  readonly property real sy: height / World.HEIGHT
  clip: true

  function isCurrent(c) {
    return current && c && current.code === c.code && current.city === c.city
  }

  function px(c) { return World.project(c.lon, c.lat)[0] * sx }
  function py(c) { return World.project(c.lon, c.lat)[1] * sy }

  // A fast pointer can leave the map without the last dot ever seeing an
  // "exited", which left its label stuck on screen. Clear it whenever the
  // pointer leaves the map as a whole.
  HoverHandler {
    onHoveredChanged: if (!hovered) root.hovered = null
  }

  // Land
  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: root.sx; yScale: root.sy }

    ShapePath {
      fillColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
      strokeColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
      strokeWidth: 0.35
      joinStyle: ShapePath.RoundJoin
      fillRule: ShapePath.WindingFill
      PathSvg { path: World.PATH }
    }
  }

  // Secure Core route: a dashed arc from the entry country to the exit city,
  // bowed a little so it reads as a route rather than a ruler line.
  Shape {
    visible: root.entry !== null
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    z: 2

    ShapePath {
      strokeColor: root.foreground
      strokeWidth: 1.2
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      strokeStyle: ShapePath.DashLine
      dashPattern: [3, 3]
      startX: root.entry ? root.px(root.entry) : 0
      startY: root.entry ? root.py(root.entry) : 0

      PathQuad {
        readonly property real x0: root.entry ? root.px(root.entry) : 0
        readonly property real y0: root.entry ? root.py(root.entry) : 0
        readonly property real x1: root.current ? root.px(root.current) : 0
        readonly property real y1: root.current ? root.py(root.current) : 0
        x: x1
        y: y1
        controlX: (x0 + x1) / 2 - (y1 - y0) * 0.25
        controlY: (y0 + y1) / 2 - Math.abs(x1 - x0) * 0.18
      }
    }
  }

  // Secure Core entry country
  Rectangle {
    visible: root.entry !== null
    width: 6; height: 6; radius: 3
    color: "transparent"
    border.color: root.foreground
    border.width: 1.5
    x: root.entry ? root.px(root.entry) - width / 2 : 0
    y: root.entry ? root.py(root.entry) - height / 2 : 0
    z: 3
  }

  // Pulse behind the connected city
  Rectangle {
    id: pulse
    visible: root.connected && root.current !== null
    width: 8; height: 8; radius: 4
    color: "transparent"
    border.color: root.foreground
    border.width: 1.5
    x: root.current ? root.px(root.current) - width / 2 : 0
    y: root.current ? root.py(root.current) - height / 2 : 0
    transformOrigin: Item.Center

    SequentialAnimation on scale {
      running: pulse.visible
      loops: Animation.Infinite
      NumberAnimation { from: 0.8; to: 3.2; duration: 1800; easing.type: Easing.OutQuad }
    }
    SequentialAnimation on opacity {
      running: pulse.visible
      loops: Animation.Infinite
      NumberAnimation { from: 0.9; to: 0.0; duration: 1800; easing.type: Easing.OutQuad }
    }
  }

  // Cities
  Repeater {
    model: root.cities

    Item {
      id: dot
      required property var modelData
      readonly property bool current: root.isCurrent(modelData)
      readonly property bool hot: root.hovered === modelData

      // A 14px hit area around a 3px dot, so it's clickable without hunting.
      width: 14; height: 14
      x: root.px(modelData) - width / 2
      y: root.py(modelData) - height / 2
      z: current ? 3 : (hot ? 2 : 1)

      Rectangle {
        anchors.centerIn: parent
        width: dot.current ? 7 : (dot.hot ? 5 : 2.5)
        height: width
        radius: width / 2
        color: dot.current || dot.hot ? root.foreground : root.dim
        opacity: dot.current ? 1.0 : (dot.hot ? 1.0 : 0.55)
        Behavior on width { NumberAnimation { duration: 90 } }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = dot.modelData
        onExited: if (root.hovered === dot.modelData) root.hovered = null
        onClicked: root.cityClicked(dot.modelData)
      }
    }
  }

  // Hover label, kept inside the map's bounds
  Rectangle {
    id: label
    visible: root.hovered !== null
    z: 10
    readonly property real dotX: root.hovered ? root.px(root.hovered) : 0
    readonly property real dotY: root.hovered ? root.py(root.hovered) : 0
    width: labelText.implicitWidth + Style.space(8)
    height: labelText.implicitHeight + Style.space(4)
    radius: Style.cornerRadius > 0 ? Style.space(3) : 0
    color: Style.controlFill(false, true, root.foreground, Commons.Color.accent)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
    border.width: 1
    x: Math.max(0, Math.min(root.width - width, dotX + 9))
    y: Math.max(0, Math.min(root.height - height, dotY - height / 2))

    Text {
      id: labelText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.hovered ? (root.hovered.city + ", " + root.hovered.code
                            + (root.hovered.load !== undefined && root.hovered.load !== null ? "  ·  " + root.hovered.load + "%" : ""))
                         : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
