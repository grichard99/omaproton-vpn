import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.grichard99.omaproton-vpn"
  ipcTarget: "io.github.grichard99.omaproton-vpn"
  manageIpc: false

  // One keyboard cursor walks every section top to bottom. Each section has a
  // name, a row count, and its own index property; sectionList() says which
  // ones exist right now.
  property string focusSection: "header"
  // Which of the two tabs under Quick Connect is showing.
  property string tab: "connections"
  readonly property var tabs: [
    { key: "connections", label: "Connections" },
    { key: "protection", label: "Protection" }
  ]
  property int tabIndex: 0
  property int nudgeIndex: 0
  property int quickIndex: 0
  property int protectionIndex: 0

  // Keyboard and mouse were fighting over the cursor. Moving with j or k
  // scrolls the list, which slides a different row under a pointer that never
  // moved; that row's hover then drags the cursor back to it and the view
  // snaps to follow, so the list walks itself backwards and you key through
  // the same rows again. Hover only counts once the pointer has actually
  // moved. The shell's PointerMoveGate does this per row from
  // onPositionChanged, which the shared Toggle and MultiSelect don't expose,
  // so it's done once here for the whole panel instead.
  property bool pointerMoved: false

  function setCursorFromHover(section, index) {
    if (!pointerMoved) return
    setCursor(section, index)
  }

  // The Protection section grows by three rows when split tunneling is on,
  // so its cursor length and the position of the sign-out row are computed
  // rather than counted by hand. The caption under the app list carries no
  // cursor of its own.
  readonly property bool splitDetailVisible: vpn.splitActive
  // The service and the dialog are private children of this panel; these are
  // what a harness needs to check the Kill Switch actually moved, and that it
  // asked first.
  readonly property string vpnKs: vpn.config["kill-switch"] || ""
  readonly property alias killSwitchDialog: killSwitchConfirm
  readonly property int protectionCount: splitDetailVisible ? 8 : 6
  readonly property int signOutIndex: protectionCount - 1

  // App paths Proton's file already holds that the scan no longer finds, kept
  // as options so an app removed from the system can still be unticked.
  readonly property var splitStaleApps: {
    var chosen = vpn.splitApps
    var out = []
    for (var i = 0; i < chosen.length; i++) {
      var path = String(chosen[i])
      var name = path.split("/").pop()
      out.push({ value: path, label: name, description: path })
    }
    return out
  }

  onSplitDetailVisibleChanged: {
    if (protectionIndex >= protectionCount) protectionIndex = protectionCount - 1
  }
  property int recentIndex: 0
  property int countryIndex: 0
  property int serverIndex: 0
  property bool cursorActive: false
  property string filterQuery: ""
  // The city that was clicked on the map: its row is scrolled into view and
  // pulses until the next click anywhere. {code, city} or null.
  property var highlight: null
  // Sign out is destructive (it disconnects too), so it takes two clicks
  // within five seconds.
  property bool signOutArmed: false

  // Drilled into one country's server list rather than the country list.
  readonly property bool drilled: vpn.serversCountry !== ""
  // Row 0 inside a drill is "Fastest in <country>"; real servers follow it.
  readonly property int serverRowCount: drilled ? vpn.servers.length + 1 : 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color iconColor: vpn.connected ? foreground : dim
  readonly property color barIconColor: vpn.connected ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property var quickActions: [
    { key: "fastest", label: "Fastest", hint: "Best server for your location", plus: false },
    { key: "random", label: "Random", hint: "Any available server", plus: false },
    { key: "p2p", label: "P2P", hint: "Optimized for file sharing", plus: true },
    { key: "securecore", label: "Secure Core", hint: "Route via a privacy-friendly country", plus: true },
    { key: "tor", label: "Tor", hint: "Tor over VPN", plus: true }
  ]

  readonly property var filteredCountries: Model.filterCountries(vpn.countries, filterQuery)

  // Offered once, until turned on or dismissed. The CLI ships with the kill
  // switch off, which means a dropped tunnel silently exposes the user.
  readonly property bool nudgeVisible: vpn.signedIn && vpn.configLoaded && vpn.stateLoaded
                                       && !vpn.killSwitchOn && !vpn.nudgeDismissed
                                       && !vpn.splitActive

  readonly property string heroMeta: {
    if (!vpn.installed) return vpn.installing ? "Installing…" : "Not installed"
    if (vpn.busy && vpn.pendingLabel !== "") return vpn.pendingLabel
    if (vpn.connected) {
      var server = Model.routeLabel(vpn.displayServer)
      if (server === "") return "Protected"
      // The feature you asked for, then the server: two hops deserve saying
      // so, and a P2P click should visibly have landed.
      if (Model.isSecureCore(vpn.displayServer)) return "\udb82\udd9d Secure Core · " + server
      if (vpn.p2pRequested && vpn.currentP2p) return "\udb81\udc97 P2P · " + server
      return server
    }
    if (!vpn.accountProbed) return "Checking…"
    if (!vpn.signedIn) return "Signed out"
    return "Not protected"
  }

  readonly property string toggleHint: vpn.connected ? "Disconnect" : "Connect to fastest server"

  function runQuick(key) {
    if (key === "fastest") vpn.connectFastest()
    else if (key === "random") vpn.connectRandom()
    else if (key === "p2p") vpn.connectP2P()
    else if (key === "securecore") vpn.connectSecureCore()
    else if (key === "tor") vpn.connectTor()
  }

  function sectionList() {
    if (!vpn.installed) return [{ name: "install", count: 1 }]
    if (!vpn.signedIn) return [{ name: "signin", count: 1 }]
    var list = [{ name: "header", count: 1 }]
    if (nudgeVisible) list.push({ name: "nudge", count: 2 })
    list.push({ name: "quick", count: quickActions.length })
    list.push({ name: "tabs", count: tabs.length })
    if (tab === "protection") {
      list.push({ name: "protection", count: protectionCount })
    } else {
      if (vpn.recents.length > 0) list.push({ name: "recents", count: vpn.recents.length })
      if (drilled) list.push({ name: "servers", count: serverRowCount })
      else if (filteredCountries.length > 0) list.push({ name: "countries", count: filteredCountries.length })
    }
    return list
  }

  function sectionIndex(name) {
    if (name === "nudge") return nudgeIndex
    if (name === "tabs") return tabIndex
    if (name === "quick") return quickIndex
    if (name === "protection") return protectionIndex
    if (name === "recents") return recentIndex
    if (name === "countries") return countryIndex
    if (name === "servers") return serverIndex
    return 0
  }

  function setSectionIndex(name, value) {
    if (name === "nudge") nudgeIndex = value
    else if (name === "tabs") tabIndex = value
    else if (name === "quick") quickIndex = value
    else if (name === "protection") protectionIndex = value
    else if (name === "recents") recentIndex = value
    else if (name === "countries") countryIndex = value
    else if (name === "servers") serverIndex = value
  }

  // Keep the cursor on a section that exists, with an index inside its rows.
  function ensureCursor() {
    var list = sectionList()
    var pos = -1
    for (var i = 0; i < list.length; i++) if (list[i].name === focusSection) pos = i
    if (pos === -1) {
      // Countries and servers stand in for each other across a drill.
      if (focusSection === "countries" && drilled) focusSection = "servers"
      else if (focusSection === "servers" && !drilled) focusSection = "countries"
      else focusSection = list[0].name
      for (i = 0; i < list.length; i++) if (list[i].name === focusSection) pos = i
      if (pos === -1) { focusSection = list[0].name; pos = 0 }
    }
    var count = list[pos].count
    setSectionIndex(focusSection, Math.max(0, Math.min(count - 1, sectionIndex(focusSection))))
  }

  // Put the Countries section header at the top of the view, and keep it
  // there while the content underneath is still changing shape.
  //
  // A drill swaps 148 country rows for a short placeholder, then the server
  // list arrives a beat later. Each of those changes the Flickable's content
  // height, and the Flickable clamps contentY to the new height the moment it
  // learns it, which is *after* any code that ran on the click. So the
  // anchor can't be a one-shot: it stays pending, is re-applied on every
  // contentHeight change, and is dropped the instant the person scrolls.
  property bool anchorPending: false

  function anchorCountrySection() {
    anchorPending = true
    applyAnchor()
    Qt.callLater(applyAnchor)
  }

  function highlightRow() {
    if (!highlight || !drilled || vpn.serversCountry !== highlight.code || !serverColumn) return null
    for (var i = 0; i < vpn.servers.length; i++) {
      if (vpn.servers[i].city === highlight.city) return serverColumn.children[i + 1] || null
    }
    return null
  }

  function applyAnchor() {
    if (!anchorPending || !panelFlick || !countrySection) return
    var target = countrySection.y
    // A map-clicked city sits just under the country header, so both the
    // "where am I" context and the pulsing row are on screen together.
    var row = highlightRow()
    if (row) target = Math.max(countrySection.y, row.mapToItem(panelFlick.contentItem, 0, 0).y - Style.space(110))
    panelFlick.contentY = Math.max(0, Math.min(root.maxScroll(), target))
  }

  function clearHighlight() { highlight = null }

  function drillInto(country) {
    if (!country) return
    // The map can be clicked from either tab; the city list lives on
    // Connections, so go there first or the drill lands on nothing.
    if (tab !== "connections") setTab("connections")
    cursorActive = true
    vpn.loadServers(country.code, country.name)
    focusSection = "servers"
    serverIndex = 0
    anchorCountrySection()
  }

  function drillOut() {
    clearHighlight()
    vpn.clearServers()
    focusSection = "countries"
    serverIndex = 0
    anchorCountrySection()
  }

  function moveCursor(dx, dy) {
    pointerMoved = false
    cursorActive = true
    ensureCursor()
    if (dy !== 0) anchorPending = false

    // Horizontal moves drill in and out of a country's server list.
    if (dx !== 0) {
      if (dx > 0 && focusSection === "countries") drillInto(filteredCountries[countryIndex])
      else if (dx < 0 && focusSection === "servers") drillOut()
      return
    }
    if (dy === 0) return

    var list = sectionList()
    var pos = 0
    for (var i = 0; i < list.length; i++) if (list[i].name === focusSection) pos = i
    var next = sectionIndex(focusSection) + dy

    if (next < 0) {
      if (pos === 0) return
      focusSection = list[pos - 1].name
      setSectionIndex(focusSection, list[pos - 1].count - 1)
    } else if (next >= list[pos].count) {
      if (pos === list.length - 1) return
      focusSection = list[pos + 1].name
      setSectionIndex(focusSection, 0)
    } else {
      setSectionIndex(focusSection, next)
    }
    if (focusSection === "header") { if (panelFlick) panelFlick.contentY = 0 }
    else scrollCursorIntoView()
  }

  function activateCursor() {
    clearHighlight()
    ensureCursor()
    if (focusSection === "install") vpn.installCli()
    else if (focusSection === "signin") submitSignIn()
    else if (focusSection === "header") vpn.toggle()
    else if (focusSection === "nudge") { if (nudgeIndex === 0) requestKillSwitch(); else vpn.dismissNudge() }
    else if (focusSection === "quick") runQuick(quickActions[quickIndex].key)
    else if (focusSection === "tabs") setTab(tabs[tabIndex].key)
    else if (focusSection === "protection") {
      if (protectionIndex === 0) requestKillSwitch()
      else if (protectionIndex === 1) vpn.toggleNetShield()
      else if (protectionIndex === 2) vpn.toggleAutoConnect()
      else if (protectionIndex === 3) requestPortForwarding()
      else if (protectionIndex === 4) vpn.toggleSplitTunnel()
      else if (splitDetailVisible && protectionIndex === 5) splitModeRow.toggle()
      else if (splitDetailVisible && protectionIndex === 6) splitAppsRow.toggle()
      else requestSignOut()
    }
    else if (focusSection === "recents") { vpn.connectRecent(recentIndex); showConnection() }
    // Enter on a country opens its servers rather than connecting blind,
    // the first row inside is still "Fastest in <country>", so the old
    // one-keystroke behaviour is only ever one row away.
    else if (focusSection === "countries") drillInto(filteredCountries[countryIndex])
    else if (focusSection === "servers") activateServerRow(serverIndex)
  }

  function activateServerRow(index) {
    if (index <= 0) {
      vpn.connectCountry(vpn.serversCountry, vpn.serversCountryName)
    } else {
      var s = vpn.servers[index - 1]
      if (!s) return
      vpn.connectServer(s.name, s.city, vpn.serversCountryName)
    }
    showConnection()
  }

  // Empty field: put the cursor in it rather than opening a terminal that
  // would only ask the same question.
  function submitSignIn() {
    var u = String(usernameField.text || "").trim()
    if (u === "") { usernameField.forceActiveFocus(); return }
    if (vpn.signIn(u)) keyCatcher.forceActiveFocus()
  }

  function maxScroll() {
    return panelFlick ? Math.max(0, panelFlick.contentHeight - panelFlick.height) : 0
  }

  // After picking a place to connect to, bring the map and connection
  // details back into view, that's what the person wants to watch next.
  function showConnection() {
    clearHighlight()
    anchorPending = false
    cursorActive = false
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  // Turning port forwarding on opens an inbound door; that deserves a
  // sentence and a click. Turning it off just closes it.
  function requestPortForwarding() {
    if (vpn.portForwardingOn) { vpn.togglePortForwarding(); return }
    portForwardConfirm.selectedIndex = 0
    portForwardConfirm.opened = true
  }

  // Whichever dimmed dialog is up owns the keyboard.
  readonly property var openDialog: killSwitchConfirm.opened ? killSwitchConfirm
                                   : (portForwardConfirm.opened ? portForwardConfirm : null)

  // Disconnected there is nothing to interrupt, so the change just happens.
  // Connected, it costs a reconnect, and that is what the dialog is for.
  function requestKillSwitch() {
    if (vpn.splitActive) return
    if (!vpn.connected) { vpn.toggleKillSwitch(); return }
    killSwitchConfirm.selectedIndex = 0
    killSwitchConfirm.opened = true
  }

  function requestSignOut() {
    if (!signOutArmed) { signOutArmed = true; signOutArm.restart(); return }
    signOutArmed = false
    vpn.signOut()
  }

  Timer { id: signOutArm; interval: 5000; onTriggered: root.signOutArmed = false }

  function setTab(key) {
    if (key !== "protection" && key !== "connections") return
    clearHighlight()
    tab = key
    tabIndex = key === "connections" ? 0 : 1
    anchorPending = false
    ensureCursor()
  }

  function setCursor(section, index) {
    cursorActive = true
    focusSection = section
    setSectionIndex(section, index)
  }

  function setHeaderCursor() {
    setCursor("header", 0)
    if (panelFlick) panelFlick.contentY = 0
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    var column = null
    if (focusSection === "nudge") column = nudgeButtons
    else if (focusSection === "quick") column = quickColumn
    else if (focusSection === "tabs") column = tabRow
    else if (focusSection === "protection") column = protectionColumn
    else if (focusSection === "recents") column = recentColumn
    else if (focusSection === "countries") column = countryColumn
    else if (focusSection === "servers") column = serverColumn
    var i = sectionIndex(focusSection)
    // The Protection column carries the Account header and rows after its
    // switches; the sign-out row is its last child wherever the cursor for it
    // has ended up.
    if (focusSection === "protection" && i === signOutIndex && column) i = column.children.length - 1
    if (column && i >= 0 && i < column.children.length) scrollItemIntoView(column.children[i])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    vpn.panelOpen = opened
    if (opened) {
      highlight = null
      anchorPending = false
      cursorActive = false
      filterQuery = ""
      vpn.clearServers()
      serverIndex = 0
      if (panelFlick) panelFlick.contentY = 0
      ensureCursor()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: vpn
    settings: root.settings
  }

  Connections {
    target: vpn
    function onSignedInChanged() { root.ensureCursor() }
    function onInstalledChanged() { root.ensureCursor() }
    function onCountriesChanged() { root.ensureCursor() }
    // Servers arrive asynchronously after a drill; re-anchor once they do.
    function onServersLoadingChanged() { if (!vpn.serversLoading && root.drilled) root.applyAnchor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(): string { vpn.connectFastest(); return "ok" }
    function disconnect(): string { vpn.disconnect(); return "ok" }
    function refresh(): string { vpn.refresh(); return "ok" }
    // Load one country's city list without opening the panel, opening it
    // steals keyboard focus, and a stray Space/Enter would connect somewhere.
    function servers(code: string): string {
      vpn.loadServers(code, code)
      return "ok"
    }
    function status(): string { return vpn.displayStatus + (vpn.displayServer !== "" ? ": " + vpn.displayServer : "") }
    // View-only controls: they change what the panel shows, never the tunnel.
    function tab(key: string): string { root.setTab(String(key)); return root.tab }
    function drill(code: string): string {
      var c = String(code || "").toUpperCase()
      if (c === "") { root.drillOut(); return "ok" }
      root.drillInto({ code: c, name: vpn.countryName(c) }); return "ok"
    }
    // "tabs" scrolls the tab strip to the top; a number is an absolute contentY.
    function scroll(to: string): string {
      if (!panelFlick) return "no panel"
      var y = String(to) === "tabs" ? tabRow.y : parseFloat(to)
      if (!isFinite(y)) return "bad value"
      root.anchorPending = false
      panelFlick.contentY = Math.max(0, Math.min(root.maxScroll(), y))
      return String(Math.round(panelFlick.contentY))
    }
    function highlight(code: string, city: string): string {
      root.drillInto({ code: String(code).toUpperCase(), name: vpn.countryName(code) })
      root.highlight = { code: String(code).toUpperCase(), city: String(city) }
      return "ok"
    }
    // Deliberately omits the account email: anything running as this user can
    // call IPC, and the panel is the only place it should be readable.
    function debug(): string {
      return JSON.stringify({
        installed: vpn.installed,
        gtkAppInstalled: vpn.gtkAppInstalled,
        accountProbed: vpn.accountProbed,
        signedIn: vpn.signedIn,
        connected: vpn.connected,
        busy: vpn.busy,
        killSwitch: vpn.config["kill-switch"] || "",
        configPending: vpn.configPending,
        splitTunneling: vpn.splitOn ? vpn.splitMode : "off",
        splitApps: vpn.splitApps.length,
        netshield: vpn.config["netshield"] || "",
        portForwarding: vpn.config["port-forwarding"] || "",
        forwardedPort: vpn.forwardedPort,
        countries: vpn.countries.length,
        recents: vpn.recents.length,
        cities: vpn.cities.length,
        traffic: { device: vpn.linkDevice, samples: vpn.rxHistory.length, rx: vpn.rxRate, tx: vpn.txRate },
        currentPlace: vpn.currentPlace ? vpn.currentPlace.city + ", " + vpn.currentPlace.code : "",
        stateLoaded: vpn.stateLoaded,
        nudgeDismissed: vpn.nudgeDismissed,
        autoConnect: vpn.autoConnect,
        autoReady: vpn.autoReady,
        linkActive: vpn.linkActive,
        statusConnected: vpn.statusConnected,
        desired: vpn._desired,
        autoWaitMs: Math.max(0, vpn._autoNextMs - Date.now()),
        pinFailed: vpn._autoPinFailed,
        drilledInto: vpn.serversCountry,
        servers: vpn.servers.length,
        lastError: vpn.lastError
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        ProtonIcon {
          anchors.centerIn: parent
          // The Proton mark is a solid triangle that fills its box corner to
          // corner, so it reads larger than the neighbouring glyphs at equal
          // size, trimmed to sit level with them.
          iconSize: Style.space(11)
          color: root.barIconColor
          opacity: vpn.connected ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vpn.toggle()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // A text field owns the keyboard while it has focus, otherwise every
      // letter typed would drive the cursor instead of the input.
      // An open Mode or Apps popup owns the keyboard while it is up, or hjkl
      // would drive the cursor on the panel behind it, scrolling a list the
      // person can't see instead of moving inside the one they opened.
      blocked: filterField.activeFocus || usernameField.activeFocus
               || splitModeRow.popupOpen || splitAppsRow.popupOpen
      onMoveRequested: function(dx, dy) {
        // A dialog with the screen dimmed behind it owns the keyboard, or the
        // cursor would be moving around underneath it unseen.
        if (root.openDialog) {
          root.openDialog.selectedIndex = root.openDialog.selectedIndex === 0 ? 1 : 0
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.openDialog) {
          if (root.openDialog.selectedIndex === 0) root.openDialog.canceled()
          else root.openDialog.confirmed()
          return
        }
        if (root.cursorActive) root.activateCursor()
      }
      // Inside a drill, escape backs out one level before it closes the panel.
      onCloseRequested: {
        if (root.openDialog) { root.openDialog.canceled(); return }
        root.drilled ? root.drillOut() : root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // No single-letter actions on purpose: the panel takes keyboard focus
      // when it opens, and a stray keystroke must never change the tunnel.
      onTextKey: function(t) {
        if (t === "/") filterField.forceActiveFocus()
      }

      // What counts as the pointer actually moving. A row sliding under a
      // still pointer reports a hover but moves no pointer, and this is how
      // the panel tells the two apart. A handler rather than a MouseArea so
      // it sees the movement without taking hover away from the rows.
      HoverHandler {
        property real lastX: -1
        property real lastY: -1
        onPointChanged: {
          var pos = point.position
          if (Math.abs(pos.x - lastX) > 1 || Math.abs(pos.y - lastY) > 1) {
            lastX = pos.x
            lastY = pos.y
            root.pointerMoved = true
          }
        }
      }

      // Changing the Kill Switch means dropping the tunnel and putting it
      // back, and for those seconds nothing is protected. That is a real cost
      // and the person paying it should agree to it first, so this asks rather
      // than doing it and narrating afterwards. Cancel is preselected: the
      // safe answer should be the one an accidental Return gives you.
      ConfirmDialog {
        id: killSwitchConfirm
        anchors.fill: parent
        z: 100
        message: (vpn.killSwitchOn ? "Turning the Kill Switch off" : "Turning the Kill Switch on")
          + " needs the tunnel down. You'll be disconnected and reconnected to the same server, "
          + "and until it comes back your traffic isn't protected."
        cancelText: "Cancel"
        confirmText: vpn.killSwitchOn ? "Turn off" : "Turn on"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: opened = false
        onConfirmed: { opened = false; vpn.toggleKillSwitch() }
      }

      ConfirmDialog {
        id: portForwardConfirm
        anchors.fill: parent
        z: 100
        message: "Port forwarding opens an inbound port on your VPN address and sends "
          + "whatever arrives on it to this computer. It's for torrent clients and only "
          + "works on P2P servers. Turn it off again when you're done."
        cancelText: "Cancel"
        confirmText: "Turn on"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: opened = false
        onConfirmed: { opened = false; vpn.togglePortForwarding() }
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
        onContentHeightChanged: root.applyAnchor()
        onMovementStarted: root.anchorPending = false

        // Fixed steps instead of Flickable's momentum: one wheel notch moves
        // about a row and a half, touchpads scroll by their pixel delta, and
        // the content never overshoots or coasts.
        WheelHandler {
          target: null
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            root.anchorPending = false
            var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y / 120) * Style.space(72)
            panelFlick.contentY = Math.max(0, Math.min(root.maxScroll(), panelFlick.contentY - dy))
            event.accepted = true
          }
        }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // The hero's trailingControl resolves `root` to PanelHero, so
            // panel state is reached through `header` instead.
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "OmaProton VPN"
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: vpn.connected ? 1.0 : 0.5
              iconComponent: Component {
                ProtonIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  // A live tunnel is enough to show the switch: you can always
                  // disconnect, even if the account probe hasn't landed.
                  visible: vpn.installed && (vpn.signedIn || vpn.connected)
                  checked: vpn.connected
                  busy: vpn.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: { root.clearHighlight(); vpn.toggle() }

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          // ── Map ─────────────────────────────────────────────────────────
          WorldMap {
            visible: vpn.signedIn && vpn.cities.length > 0
            width: parent.width
            cities: vpn.cities
            current: vpn.currentPlace
            connected: vpn.connected
            foreground: root.foreground
            fontFamily: root.fontFamily
            onCityClicked: function(c) {
              root.drillInto({ code: c.code, name: vpn.countryName(c.code) })
              root.highlight = { code: c.code, city: c.city }
            }
          }

          Text {
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : vpn.lastError
            textFormat: Text.PlainText
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ── First run: the CLI isn't there yet ──────────────────────────
          Column {
            visible: !vpn.installed
            width: parent.width
            spacing: Style.space(8)

            ActionRow {
              width: parent.width
              hasCursor: root.cursorActive && root.focusSection === "install"
              icon: "󰇚"
              title: vpn.installing ? "Installing Proton VPN CLI…" : "Install Proton VPN CLI"
              subtitle: vpn.installing ? "Finish the install in the terminal that opened" : "Opens a terminal: Omarchy handles the install"
              enabled: !vpn.installing
              onEntered: root.setCursorFromHover("install", 0)
              onClicked: vpn.installCli()
            }

            Text {
              width: parent.width
              text: "You'll also need a Proton account. A free one works: sign up at proton.me if you don't have one yet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // The GTK app and the CLI can't both run; say so before connect fails.
          Text {
            visible: vpn.gtkAppInstalled
            width: parent.width
            text: "The Proton VPN desktop app is installed. It can't run alongside the CLI this widget uses. Quit the app before connecting, or remove it from the Omarchy menu under Remove → Package."
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ── Sign in ─────────────────────────────────────────────────────
          Column {
            // Held back until the account probe lands, and never shown over a
            // live tunnel, a connection is proof the session is valid.
            visible: vpn.installed && vpn.accountProbed && !vpn.signedIn && !vpn.connected
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: usernameField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Proton username or email"
              Keys.onEscapePressed: function(event) {
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) {
                root.submitSignIn()
                event.accepted = true
              }
            }

            ActionRow {
              width: parent.width
              hasCursor: root.cursorActive && root.focusSection === "signin"
              icon: "󰌆"
              title: "Sign in with Proton"
              subtitle: "Opens a terminal for your password and 2FA code"
              onEntered: root.setCursorFromHover("signin", 0)
              onClicked: root.submitSignIn()
            }
          }

          // ── Connection detail ───────────────────────────────────────────
          // Server and location are promoted out of the status parse;
          // everything else the CLI printed (Load, Protocol, …) is rendered
          // as-is.
          Column {
            visible: vpn.connected
            width: parent.width
            spacing: Style.spacing.labelGap

            // The server, and the feature it's serving: the route for Secure
            // Core, P2P when that's what you asked for. Same rule as the header.
            InfoPair {
              label: "Server"
              value: {
                var name = vpn.displayServer
                if (Model.isSecureCore(name)) return Model.routeLabel(name) + " · Secure Core"
                if (vpn.p2pRequested && vpn.currentP2p) return name + " · P2P"
                return name
              }
            }
            InfoPair { visible: vpn.location !== ""; label: "Location"; value: vpn.location }
            CopyPair {
              visible: vpn.forwardedPort !== ""
              label: "Forwarded port"
              value: vpn.forwardedPort
              copied: root.portCopied
              onCopy: root.copyPort()
            }

            Repeater {
              model: vpn.fields
              InfoPair {
                required property var modelData
                label: modelData.label
                value: modelData.value
              }
            }
          }

          // ── Traffic ─────────────────────────────────────────────────────
          Traffic {
            // Only over a live, settled tunnel: not while connecting or
            // disconnecting, and gone the instant a disconnect is asked for.
            visible: vpn.connected && vpn.linkActive && !vpn.busy && vpn.rxHistory.length > 0
            width: parent.width
            rxHistory: vpn.rxHistory
            txHistory: vpn.txHistory
            rxRate: vpn.rxRate
            txRate: vpn.txRate
            sessionRx: vpn.sessionRx
            sessionTx: vpn.sessionTx
            uptimeSec: vpn.uptimeSec
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // ── Kill-switch nudge ───────────────────────────────────────────
          BorderSurface {
            visible: root.nudgeVisible
            width: parent.width
            implicitHeight: nudgeContent.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Style.controlFill(false, false, root.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

            Column {
              id: nudgeContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(6)

              Text {
                width: parent.width
                text: "Turn on the Kill Switch?"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: "If the VPN ever drops, your internet is blocked until it's back, so you're never exposed without noticing. Recommended."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Row {
                id: nudgeButtons
                spacing: Style.space(8)

                Button {
                  // Held through the re-read too, so the button stops saying
                  // "Turning on…" at the same moment the switch flips.
                  text: vpn.configPending === "kill-switch" ? "Turning on…" : "Turn on"
                  bordered: true
                  foreground: root.foreground
                  hasCursor: root.cursorActive && root.focusSection === "nudge" && root.nudgeIndex === 0
                  enabled: vpn.configPending === ""
                  onClicked: root.requestKillSwitch()
                }

                Button {
                  text: "Not now"
                  foreground: root.dim
                  hasCursor: root.cursorActive && root.focusSection === "nudge" && root.nudgeIndex === 1
                  onClicked: vpn.dismissNudge()
                }
              }
            }
          }

          PanelSeparator {
            visible: vpn.signedIn
            foreground: root.foreground
          }

          // ── Quick connect ───────────────────────────────────────────────
          Column {
            visible: vpn.signedIn
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "QUICK CONNECT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: quickColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.quickActions
                ActionRow {
                  required property var modelData
                  required property int index
                  width: quickColumn.width
                  hasCursor: root.cursorActive && root.focusSection === "quick" && root.quickIndex === index
                  title: modelData.label
                  subtitle: modelData.hint
                  // Secure Core gets an ACTIVE tag; P2P doesn't, since most
                  // servers permit it and the header already says when you
                  // asked for it.
                  trailing: modelData.key === "securecore" && vpn.connected && Model.isSecureCore(vpn.displayServer)
                            ? "ACTIVE" : (modelData.plus ? "PLUS" : "")
                  enabled: !vpn.busy
                  onEntered: root.setCursorFromHover("quick", index)
                  onClicked: root.runQuick(modelData.key)
                }
              }
            }
          }

          PanelSeparator {
            visible: vpn.signedIn
            foreground: root.foreground
          }

          // ── Tabs ────────────────────────────────────────────────────────
          // Same pill strip as the network panel's DNS provider row.
          Row {
            id: tabRow
            visible: vpn.signedIn
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * (root.tabs.length - 1)) / root.tabs.length

            Repeater {
              model: root.tabs
              TabPill {
                required property var modelData
                required property int index
                width: tabRow.cellWidth
                tabKey: modelData.key
                text: modelData.label
                tabIdx: index
              }
            }
          }

          // ── Protection ──────────────────────────────────────────────────
          Column {
            visible: vpn.signedIn && root.tab === "protection"
            width: parent.width
            spacing: Style.space(10)

            Column {
              id: protectionColumn
              width: parent.width
              spacing: Style.space(6)

              Toggle {
                width: parent.width
                label: "Kill Switch"
                // Says what the click will cost before it is clicked: pausing
                // split tunneling, or a reconnect, both of which used to be
                // things you found out afterwards.
                description: {
                  var applying = vpn.configPendingLabel("kill-switch")
                  if (applying !== "") return applying
                  if (!vpn.configLoaded) return "Loading…"
                  if (vpn.splitActive) return "Turn split tunneling off to use this"
                  if (vpn.connected) return "Blocks internet if the VPN drops, changing it reconnects"
                  return "Block internet if the VPN drops"
                }
                checked: vpn.killSwitchOn
                enabled: vpn.configLoaded && vpn.configPending === "" && !vpn.splitActive
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursorFromHover("protection", 0) }
                onClicked: { root.clearHighlight(); root.requestKillSwitch() }
              }

              Toggle {
                width: parent.width
                label: "NetShield · PLUS"
                description: {
                  var applying = vpn.configPendingLabel("netshield")
                  if (applying !== "") return applying
                  if (!vpn.configLoaded) return "Loading…"
                  var v = String(vpn.config["netshield"] || "off")
                  if (v === "malware-ads-trackers") return "Blocking malware, ads and trackers"
                  if (v === "malware-only") return "Blocking malware"
                  return "Block malware, ads and trackers"
                }
                checked: vpn.netShieldOn
                enabled: vpn.configLoaded && vpn.configPending === ""
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursorFromHover("protection", 1) }
                onClicked: { root.clearHighlight(); vpn.toggleNetShield() }
              }

              // Widget-owned, unlike the two above: the CLI has no setting for
              // this, so it lives in the widget's own state file.
              Toggle {
                width: parent.width
                label: "Always On"
                description: "Reconnects on boot and interruptions"
                checked: vpn.autoConnect
                enabled: !vpn.busy
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === 2
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursorFromHover("protection", 2) }
                onClicked: { root.clearHighlight(); vpn.toggleAutoConnect() }
              }

              Toggle {
                width: parent.width
                label: "Port forwarding"
                description: {
                  var applying = vpn.configPendingLabel("port-forwarding")
                  if (applying !== "") return applying
                  if (!vpn.configLoaded) return "Loading…"
                  if (!vpn.portForwardingOn) return "For torrent clients, on P2P servers"
                  if (vpn.forwardedPort !== "") return "Port " + vpn.forwardedPort + " on this server"
                  if (vpn.connected) return "Needs a P2P server: Quick connect → P2P"
                  return "Connect to a P2P server to get a port"
                }
                checked: vpn.portForwardingOn
                enabled: vpn.configLoaded && vpn.configPending === ""
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === 3
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursorFromHover("protection", 3) }
                onClicked: { root.clearHighlight(); root.requestPortForwarding() }
              }


              // Proton skips split tunneling entirely while the kill switch
              // is on, so the row says that instead of offering a switch that
              // would look on and do nothing.
              Toggle {
                width: parent.width
                label: "Split tunneling"
                description: vpn.splitDescription()
                checked: vpn.splitActive
                enabled: vpn.splitAvailable && !vpn.splitBlocked
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === 4
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursorFromHover("protection", 4) }
                onClicked: { root.clearHighlight(); vpn.toggleSplitTunnel() }
              }

              Dropdown {
                id: splitModeRow
                visible: root.splitDetailVisible
                width: parent.width
                label: "Mode"
                value: vpn.splitMode
                options: [
                  { value: "exclude", label: "Exclude: chosen apps skip the VPN" },
                  { value: "include", label: "Include: only chosen apps use the VPN" }
                ]
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === 5
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursorFromHover("protection", 5) }
                onChanged: function(value) { vpn.setSplitMode(value) }
              }

              // The list is scanned fresh each time the popup opens, so an app
              // installed since the panel loaded is there without a restart.
              // Paths already in Proton's file that no longer scan (an app
              // that was removed) are added back as options, otherwise they
              // could never be unticked.
              MultiSelect {
                id: splitAppsRow
                visible: root.splitDetailVisible
                width: parent.width
                label: "Apps"
                options: root.splitStaleApps
                optionsCommand: ["python3", vpn.appsScriptPath]
                placeholderText: "Search apps..."
                emptyText: "No apps found"
                noSelectionText: "None chosen"
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === 6
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursorFromHover("protection", 6) }
                onChanged: function(values) { vpn.setSplitApps(values) }
              }

              // MultiSelect writes to its own `values` when a row is ticked,
              // and that imperative write destroys a plain declarative
              // binding: from the first tick on, the list would show what was
              // clicked rather than what is in the file. The visible symptom
              // was a mode switch leaving the previous mode's apps on screen
              // while Proton had none, which reads as "it kept my apps" when
              // the truth is the opposite. Binding reasserts itself every time
              // the service's list changes, so the file stays the one source.
              Binding {
                target: splitAppsRow
                property: "values"
                value: vpn.splitApps
              }

              Text {
                visible: root.splitDetailVisible
                width: parent.width
                text: "Restart each chosen app after connecting, or it keeps using the tunnel it started on."
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              // ── Account ─────────────────────────────────────────────────
              PanelSectionHeader {
                text: "ACCOUNT"
                foreground: root.foreground
                fontFamily: root.fontFamily
                topPadding: Style.space(10)
              }

              Column {
                width: parent.width
                spacing: Style.spacing.labelGap
                InfoPair { label: "Signed in as"; value: vpn.account }
                InfoPair { visible: vpn.plan !== ""; label: "Plan"; value: vpn.plan }
              }

              ActionRow {
                width: parent.width
                hasCursor: root.cursorActive && root.focusSection === "protection" && root.protectionIndex === root.signOutIndex
                icon: "󰍃"
                title: root.signOutArmed ? "Click again to sign out" : "Sign out"
                subtitle: root.signOutArmed ? "Disconnects and clears the session on this computer" : "You'll need your password and 2FA to sign back in"
                enabled: !vpn.busy
                onEntered: root.setCursorFromHover("protection", root.signOutIndex)
                onClicked: root.requestSignOut()
              }
            }
          }

          // ── Recent ──────────────────────────────────────────────────────
          Column {
            visible: vpn.signedIn && root.tab === "connections" && vpn.recents.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "RECENT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: recentColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: vpn.recents
                ActionRow {
                  required property var modelData
                  required property int index
                  width: recentColumn.width
                  hasCursor: root.cursorActive && root.focusSection === "recents" && root.recentIndex === index
                  title: modelData.title || ""
                  subtitle: modelData.subtitle || ""
                  enabled: !vpn.busy
                  onEntered: root.setCursorFromHover("recents", index)
                  onClicked: { vpn.connectRecent(index); root.showConnection() }
                }
              }
            }
          }

          // ── Countries / cities ──────────────────────────────────────────
          Column {
            id: countrySection
            visible: vpn.signedIn && root.tab === "connections"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.drilled ? String(vpn.serversCountryName).toUpperCase() : "COUNTRIES"
              textFormat: Text.PlainText
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            BackRow {
              visible: root.drilled
              width: parent.width
            }

            Text {
              visible: root.drilled && vpn.serversLoading
              width: parent.width
              text: "Loading servers…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: serverColumn
              visible: root.drilled && !vpn.serversLoading
              width: parent.width
              spacing: Style.space(6)

              FastestRow { width: serverColumn.width }

              Repeater {
                model: vpn.servers
                ServerRow {
                  required property var modelData
                  required property int index
                  width: serverColumn.width
                  server: modelData
                  // Row 0 is "Fastest in <country>", so servers start at 1.
                  rowIndex: index + 1
                }
              }
            }

            TextField {
              id: filterField
              visible: !root.drilled
              width: parent.width
              foreground: root.foreground
              placeholderText: vpn.countriesLoaded ? "Filter countries  (press /)" : "Loading countries…"
              enabled: vpn.countriesLoaded
              text: root.filterQuery
              onTextChanged: {
                root.filterQuery = text
                root.countryIndex = 0
              }
              Keys.onEscapePressed: function(event) {
                if (text !== "") text = ""
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) {
                var c = root.filteredCountries[0]
                if (c) {
                  vpn.connectCountry(c.code, c.name)
                  keyCatcher.forceActiveFocus()
                  root.showConnection()
                }
                event.accepted = true
              }
            }

            Text {
              visible: !root.drilled && vpn.countriesLoaded && root.filteredCountries.length === 0
              width: parent.width
              text: "No countries match."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: countryColumn
              visible: !root.drilled
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.filteredCountries
                CountryRow {
                  required property var modelData
                  required property int index
                  width: countryColumn.width
                  country: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  // A clickable row: optional icon, title + subtitle, optional trailing tag.
  // Used for install, sign-in, quick connect, and recents so they all read
  // the same way.
  component ActionRow: CursorSurface {
    id: actionRow
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    signal entered()
    signal clicked()

    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX
    opacity: enabled ? 1.0 : 0.6

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: actionRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: actionRow.enabled
      onEntered: actionRow.entered()
      onClicked: { root.clearHighlight(); actionRow.clicked() }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        visible: actionRow.icon !== ""
        text: actionRow.icon
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: actionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.title
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: actionRow.subtitle !== ""
          text: actionRow.subtitle
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: actionRow.trailing !== ""
        text: actionRow.trailing
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component TabPill: Button {
    id: pill
    property string tabKey: ""
    property int tabIdx: 0

    fontSize: Style.font.bodySmall
    foreground: root.foreground
    fontFamily: root.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true
    active: root.tab === tabKey
    hasCursor: root.cursorActive && root.focusSection === "tabs" && root.tabIndex === tabIdx

    onHovered: function(isHovered) { if (isHovered) root.setCursorFromHover("tabs", pill.tabIdx) }
    onClicked: root.setTab(tabKey)   // setTab clears the highlight
  }

  component CountryRow: CursorSurface {
    id: countryRow
    property var country: null
    property int rowIndex: 0

    readonly property bool isCurrent: vpn.connected && vpn.displayServer !== "" && country
                                      && vpn.displayServer.toUpperCase().indexOf(String(country.code).toUpperCase()) === 0

    hasCursor: root.cursorActive && root.focusSection === "countries" && root.countryIndex === rowIndex
    foreground: root.foreground

    implicitHeight: countryContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onEntered: root.setCursorFromHover("countries", countryRow.rowIndex)
      onClicked: { root.clearHighlight(); root.drillInto(countryRow.country) }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: countryContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: countryRow.country ? countryRow.country.name : ""
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      Text {
        text: countryRow.isCurrent ? "󰄬" : (countryRow.country ? countryRow.country.code : "")
        textFormat: Text.PlainText
        color: countryRow.isCurrent ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      // Signals that the row opens a server list rather than connecting.
      Text {
        text: "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component BackRow: CursorSurface {
    id: backRow
    foreground: root.foreground
    implicitHeight: backLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.drillOut()
    }

    Text {
      id: backLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      text: "‹  All countries"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Row 0 of a drill: keeps the old one-click "fastest in this country" path.
  component FastestRow: CursorSurface {
    id: fastestRow
    hasCursor: root.cursorActive && root.focusSection === "servers" && root.serverIndex === 0
    foreground: root.foreground
    implicitHeight: fastestContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onEntered: root.setCursorFromHover("servers", 0)
      onClicked: { root.clearHighlight(); root.activateServerRow(0) }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: fastestContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: "Fastest in " + vpn.serversCountryName
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: vpn.servers.length > 0 ? vpn.servers.length + (vpn.servers.length === 1 ? " city" : " cities") + " available" : "Let Proton choose"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component ServerRow: CursorSurface {
    id: serverRow
    property var server: null
    property int rowIndex: 0

    // The row stands for a city, so any server in that city counts as current,
    // status reports "NL#42 in Amsterdam, Netherlands", so match on location.
    readonly property bool isCurrent: vpn.connected && server
                                      && (vpn.displayServer === server.name
                                          || (server.city !== "" && String(vpn.location).indexOf(server.city) === 0))

    hasCursor: root.cursorActive && root.focusSection === "servers" && root.serverIndex === rowIndex
    foreground: root.foreground
    implicitHeight: serverContent.implicitHeight + Style.spacing.rowPaddingX

    // The city that was clicked on the map breathes until the next click.
    readonly property bool pulsing: root.highlight !== null && server
                                    && root.highlight.code === vpn.serversCountry
                                    && root.highlight.city === server.city
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "transparent"
      border.color: root.foreground
      border.width: 1.5
      visible: serverRow.pulsing
      SequentialAnimation on opacity {
        running: serverRow.pulsing
        loops: Animation.Infinite
        NumberAnimation { from: 0.25; to: 0.95; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.95; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onEntered: root.setCursorFromHover("servers", serverRow.rowIndex)
      onClicked: { root.clearHighlight(); if (serverRow.server) root.activateServerRow(serverRow.rowIndex) }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: serverContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: serverRow.server ? serverRow.server.city : ""
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: {
            if (!serverRow.server) return ""
            var bits = [serverRow.server.name]
            // Tier 0 is Proton's free tier, the one thing a free user needs
            // to know before clicking.
            if (serverRow.server.tier === 0) bits.push("Free")
            var tags = serverRow.server.tags || []
            if (tags.length > 0) bits.push(tags.join(", "))
            return bits.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        text: serverRow.isCurrent ? "󰄬" : (serverRow.server && serverRow.server.load !== undefined && serverRow.server.load !== null ? serverRow.server.load + "%" : "")
        textFormat: Text.PlainText
        color: {
          if (serverRow.isCurrent) return root.foreground
          var load = serverRow.server ? serverRow.server.load : 0
          return load >= 85 ? root.urgent : root.dim
        }
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // A 2 s "Copied" flash on the forwarded port row.
  property bool portCopied: false
  Timer { id: portCopiedTimer; interval: 2000; onTriggered: root.portCopied = false }
  function copyPort() {
    vpn.copyForwardedPort()
    portCopied = true
    portCopiedTimer.restart()
  }

  // An InfoPair you click to copy the value. The value carries a copy glyph
  // and flips to "Copied" for a moment, so a torrent client is one paste away.
  component CopyPair: Item {
    id: copyPair
    property string label: ""
    property string value: ""
    property bool copied: false
    signal copy()

    width: parent.width
    implicitHeight: copyRow.implicitHeight
    height: implicitHeight

    // A Row can't hold an anchored MouseArea, so the row and the click
    // target are siblings under this Item.
    Row {
      id: copyRow
      width: parent.width
      spacing: Style.space(8)

      InfoLabel { text: copyPair.label }
      Item {
        width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
        height: 1
      }
      InfoValue {
        text: copyPair.copied ? "Copied" : copyPair.value + "  󰆏"
        opacity: copyArea.containsMouse || copyPair.copied ? 1.0 : 0.85
      }
    }

    MouseArea {
      id: copyArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: copyPair.copy()
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    textFormat: Text.PlainText
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
