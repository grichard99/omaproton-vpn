import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One line of typed text, drawn like the kit's text field.
//
// Everything in here arrives from the keyboard. The field never takes text
// from the clipboard: the paste keys and a middle click do nothing, so what
// another program has copied is never read by the panel. Copying out of the
// field still works.
//
// Text is plain and stays on one line. Line breaks and control characters
// are dropped as they arrive, and `maximumLength` (0 for no limit) is
// enforced on every change, whatever produced it.
FocusScope {
  id: root

  property alias text: edit.text
  property string placeholderText: ""
  property int maximumLength: 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  // Panel-cursor flag, painted like a hover while the field is not focused.
  property bool hasCursor: false

  // Return or Enter, and Escape.
  signal accepted()
  signal cancelled()

  readonly property bool _focused: edit.activeFocus
  readonly property bool _hot: hover.hovered || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)
  readonly property real _left: Style.spacing.controlPaddingX + Border.left(_borderSpec)
  readonly property real _right: Style.spacing.controlPaddingX + Border.right(_borderSpec)
  readonly property real _top: Style.spacing.inputPaddingY + Border.top(_borderSpec)
  readonly property real _bottom: Style.spacing.inputPaddingY + Border.bottom(_borderSpec)

  // How far the text is slid left so the caret stays in view.
  property real _scroll: 0
  property bool _tidying: false

  implicitWidth: Style.space(200)
  implicitHeight: Math.ceil(metrics.height) + _top + _bottom

  // Empty the field without disturbing a binding on `text`.
  function clear() { edit.clear() }

  // Slide the line so the caret is always inside the box, the way a
  // single-line field does when the text is wider than it is.
  function _follow() {
    var caret = edit.cursorRectangle
    var room = view.width
    var s = _scroll
    if (caret.x - s < 0) s = caret.x
    else if (caret.x + caret.width - s > room) s = caret.x + caret.width - room
    var most = Math.max(0, edit.implicitWidth - room)
    _scroll = Math.max(0, Math.min(s, most))
  }

  // Remove what a one-line plain field can't hold. Uses the editor's own
  // remove() so a binding on `text` survives.
  function _tidy() {
    if (_tidying) return
    _tidying = true
    try {
      var value = edit.text
      for (var i = value.length - 1; i >= 0; i--) {
        var c = value.charCodeAt(i)
        if (c < 32 || c === 127 || c === 0x2028 || c === 0x2029) edit.remove(i, i + 1)
      }
      if (maximumLength > 0 && edit.length > maximumLength) edit.remove(maximumLength, edit.length)
    } finally {
      _tidying = false
    }
  }

  FontMetrics {
    id: metrics
    font: edit.font
  }

  HoverHandler { id: hover }

  BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }

  // A click on the padding lands in the field too.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onPressed: function(mouse) {
      edit.forceActiveFocus()
      edit.cursorPosition = edit.length
      mouse.accepted = true
    }
  }

  Item {
    id: view
    anchors.fill: parent
    anchors.leftMargin: root._left
    anchors.rightMargin: root._right
    anchors.topMargin: root._top
    anchors.bottomMargin: root._bottom
    clip: true
    onWidthChanged: root._follow()

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      visible: edit.length === 0 && edit.preeditText === ""
      text: root.placeholderText
      textFormat: Text.PlainText
      elide: Text.ElideRight
      font: edit.font
      color: Qt.darker(root.foreground, 1.6)
    }

    TextEdit {
      id: edit
      x: -root._scroll
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(view.width, implicitWidth)
      focus: true
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.NoWrap
      selectByMouse: true
      selectByKeyboard: true
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground

      onTextChanged: root._tidy()
      onCursorRectangleChanged: root._follow()

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        // Typed text only: the paste keys end here.
        if (event.matches(StandardKey.Paste) || event.key === Qt.Key_Paste) {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.accepted()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Escape) {
          root.cancelled()
          event.accepted = true
          return
        }
        // A tab would be typed into the line; there is nowhere for it to go.
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) event.accepted = true
      }
    }

    // Middle click is the other way text gets pasted. Swallow it here and
    // let every other button through to the editor underneath.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.MiddleButton
      cursorShape: Qt.IBeamCursor
      onPressed: function(mouse) { mouse.accepted = true }
    }
  }
}
