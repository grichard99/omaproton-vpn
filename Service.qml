import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Proton VPN state for the bar widget.
//
// Two polls with different costs drive this:
//
//   * nmcli (~10ms) runs on a short interval and owns the bar icon. The CLI
//     names its tunnel "ProtonVPN <server>" on device proton0, so this alone
//     answers "are we up, and where" without paying for the Python CLI.
//   * `protonvpn status` (~1s of Python start-up) runs only when the panel is
//     open, on demand, and after an action, it supplies the detail rows.
//
// `protonvpn connect` blocks for 30-60s, so every action is optimistic:
// _desired pins the UI to the requested state until reality agrees.
//
// Every subprocess is an argv list. The one place a value crosses a shell
// boundary is sign-in, where the username is whitelisted and single-quoted
// before it reaches the terminal launcher.
Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  property bool installed: false
  property bool installing: false
  // The GTK app and the CLI share one backend and can't run at the same time;
  // a user who installed the app from Proton's site hits an opaque failure.
  property bool gtkAppInstalled: false

  property bool signedIn: false
  // `protonvpn info` costs ~1s, so signedIn is false-but-unknown until the
  // first probe lands. Without this the widget briefly claims "Signed out"
  // over a tunnel that is plainly up.
  property bool accountProbed: false
  property string account: ""
  property string plan: ""

  // nmcli-derived, fast
  property bool linkActive: false
  property string linkServer: ""

  // `protonvpn status`-derived, slow
  property bool statusConnected: false
  property bool statusConnecting: false
  property string statusText: "Checking…"
  property string serverName: ""
  property string location: ""
  property var fields: []

  property var countries: []
  property bool countriesLoaded: false

  // Server drill-down for one country, read from the client's own cache.
  property var servers: []
  property string serversCountry: ""
  property string serversCountryName: ""
  property bool serversLoading: false

  // Every Proton city with coordinates, for the mini-map. From the client's
  // cache too, so it exists as soon as the user has connected once.
  property var cities: []
  property bool citiesLoaded: false
  // {code, city, lat, lon} for the server we're on, or null.
  property var currentPlace: null
  property string _locatePending: ""

  // Tunnel throughput, from the kernel's own counters for the tunnel
  // interface (/sys/class/net/<dev>/statistics). Sampled once a second, only
  // while the panel is open and a tunnel is up, zero cost otherwise.
  property string linkDevice: ""
  property var rxHistory: []
  property var txHistory: []
  property real rxRate: 0
  property real txRate: 0
  property real sessionRx: 0
  property real sessionTx: 0
  property int uptimeSec: 0
  property real _lastRx: -1
  property real _lastTx: -1
  property real _lastSampleMs: 0
  property real _linkUpMs: 0
  readonly property int trafficSamples: 60

  // `protonvpn config list`, keyed by setting name.
  property var config: ({})
  property bool configLoaded: false
  readonly property bool killSwitchOn: String(config["kill-switch"] || "") === "standard"
  readonly property bool netShieldOn: configLoaded && String(config["netshield"] || "off") !== "off"
  readonly property bool portForwardingOn: configLoaded && String(config["port-forwarding"] || "off") === "on"
  // The only values setConfig() will ever pass to the CLI.
  readonly property var configValues: ({
    "kill-switch": ["off", "standard"],
    "netshield": ["off", "malware-only", "malware-ads-trackers"],
    "port-forwarding": ["off", "on"]
  })

  // The port Proton assigned on a P2P server, or "" when there isn't one.
  //
  // Proton hands it out over NAT-PMP on the tunnel gateway and drops the
  // mapping unless it's renewed, which is why Proton's guide runs natpmpc in
  // a loop. The CLI's own agent does the same exchange but only while a
  // `protonvpn` process is alive, so a bare `status` poll rarely completes
  // it. port.py is that exchange: while the switch is on and the tunnel is
  // up it runs every 45 s (the guide's cadence against a 60 s lifetime),
  // which both shows the port and keeps it. It's the one network request
  // the widget makes, to 10.2.0.1 inside the tunnel, never anywhere else.
  property string forwardedPort: ""
  readonly property string portScriptPath: Qt.resolvedUrl("port.py").toString().replace(/^file:\/\//, "")
  readonly property bool portWanted: portForwardingOn && connected && linkActive && !busy

  onPortWantedChanged: {
    if (portWanted) refreshPort()
    else forwardedPort = ""
  }

  function refreshPort() {
    if (!portWanted || portProcess.running) return
    portProcess.command = ["python3", portScriptPath]
    portProcess.running = true
  }

  onConnectedChanged: if (!connected) forwardedPort = ""

  // Copy is the only thing the widget ever does with the port.
  function copyForwardedPort() {
    if (forwardedPort === "") return
    Quickshell.execDetached(["wl-copy", "--", forwardedPort])
  }

  // Persisted across restarts: last few places connected to, and whether the
  // kill-switch nudge was dismissed. Location labels only, nothing secret.
  property var recents: []
  property bool nudgeDismissed: false
  property bool stateLoaded: false

  // ── Always On ───────────────────────────────────────────────────────────
  // One invariant, not a set of triggers: if the switch is on and the tunnel
  // isn't up, bring it up. Signing in, joining a network and a dropped tunnel
  // are all just moments when that stops being true, so the nmcli poll that
  // already runs for the bar icon is the whole mechanism. No second watcher,
  // no second process, nothing to keep in sync.
  //
  // The CLI has no always-on mode of its own, and NetworkManager can't own it
  // either: the CLI re-creates its WireGuard profile on every connect, so an
  // NM autoconnect flag would only fight it.
  property bool autoConnect: false
  // Set when an automatic connect fails, so the next attempt falls back to
  // Fastest instead of retrying a server that is full or gone, forever.
  property bool _autoPinFailed: false
  // Don't retry a failed connect on the very next poll: `protonvpn connect`
  // against a dead network fails slowly and there is no point hammering it.
  readonly property int autoRetryMs: 30000
  property real _autoNextMs: 0
  // True while the in-flight connect was started by the reconciler rather
  // than a click, so only its failures arm the retry delay.
  property bool _autoAttempt: false

  readonly property bool autoReady: installed && signedIn && accountProbed && stateLoaded && autoConnect
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-protonvpn"
  readonly property string statePath: stateDir + "/state.json"

  readonly property string scriptPath: Qt.resolvedUrl("servers.py").toString().replace(/^file:\/\//, "")
  readonly property string appsScriptPath: Qt.resolvedUrl("apps.py").toString().replace(/^file:\/\//, "")

  property string actionStatus: ""
  property string lastError: ""
  property string pendingLabel: ""

  // -1 = follow reality; 0/1 = a requested state still catching up.
  property int _desired: -1
  // Set when we asked for the tunnel to go down, so the drop isn't reported
  // as a failure.
  property bool _expectDown: false
  // What the in-flight connect was asked for, recorded to recents on success.
  property var _target: null
  // When the last action finished, and when the in-flight link poll started.
  // A poll that began before the action ended carries pre-action data, so it
  // must not be used to decide whether the action took effect.
  property real _actionEndedMs: 0
  property real _watchStartedMs: 0
  property string _configKey: ""
  property string _configValue: ""

  readonly property bool connected: _desired === -1 ? (linkActive || statusConnected) : (_desired === 1)
  readonly property bool busy: actionProcess.running || connectProcess.running

  // Every `protonvpn` call is a fresh Python process that loads, and may
  // rewrite, Proton's shared 24MB server cache. The CLI takes no lock on it:
  // two processes refreshing at once can race and leave every server in that
  // file marked down, at which point the CLI refuses to pick a server at all
  // ("No servers found matching criteria") until the list is refetched, which
  // it will not do while its own copy looks fresh.
  //
  // So the read-only probes take turns, and stand aside while an action the
  // person asked for is running. Actions are already serialized by `busy`.
  // This also cuts a connect from ~9-15 CLI processes down to one.
  // Deliberately a plain flag, not a binding over the Process objects. A
  // binding does not re-evaluate between two statements of the same function,
  // so refresh()'s `refreshStatus(); refreshAccount();` would both read "not
  // busy" and start together: exactly the pair that raced and corrupted the
  // cache. This is set the instant a probe launches and cleared when it exits.
  property bool _probeRunning: false
  readonly property bool cliBusy: _probeRunning || busy
  // One flag per probe that stepped aside, so each is retried rather than
  // lost. Deliberately not a single shared flag: the two frequent probes
  // (status, info) always have work to do, so a shared flag lets them take
  // the slot forever and starve the country and config loads.
  property bool _wantStatus: false
  property bool _wantAccount: false
  property bool _wantCountries: false
  property bool _wantConfig: false
  readonly property bool _probesPending: _wantStatus || _wantAccount || _wantCountries || _wantConfig
  readonly property bool refreshing: statusProcess.running
  // Which config key is mid-change, "" when nothing is, and the value it's
  // heading for. A click costs two CLI runs, `config set` then the `config
  // list` re-read that confirms it, about 1.4s of CLI startup between them,
  // and the switch can't move until the second lands. Rather than throw the
  // knob early and hope, the row keeps showing the value the CLI last
  // reported and says what it's doing, the same way displayStatus says
  // "Connecting…". Cleared by the re-read, so it covers both runs.
  property string configPending: ""
  property string configPendingValue: ""

  // "" unless that row is the one mid-change.
  function configPendingLabel(key) {
    if (configPending !== key) return ""
    return configPendingValue === "off" ? "Turning off…" : "Turning on…"
  }

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property int watchIntervalSec: intSetting("watchIntervalSec", 4, 2, 60)
  readonly property bool notificationsOn: String(setting("notifications", "on")) !== "off"

  // The server line from nmcli is live even mid-`connect`; prefer it, and fall
  // back to the status parse when the link is down.
  readonly property string displayServer: linkActive && linkServer !== "" ? linkServer : serverName
  // Observed state outranks account state: a live tunnel is a fact, while
  // signedIn is unknown until the first probe returns.
  readonly property string displayStatus: {
    if (!installed) return "Not installed"
    if (busy && pendingLabel !== "") return pendingLabel
    if (connected) return "Protected"
    if (statusConnecting) return "Connecting…"
    if (!accountProbed) return "Checking…"
    if (!signedIn) return "Signed out"
    return "Not protected"
  }

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

  function refresh() {
    if (!installed) {
      probeInstalled()
      return
    }
    watchLink()
    // Account first: `signedIn` gates the map, the tabs and every setting, so
    // probing it before the detail rows is what stops the panel looking empty
    // for the first few seconds after a shell restart.
    refreshAccount()
    refreshStatus()
  }

  function probeInstalled() {
    if (!whichProcess.running) {
      whichProcess.command = ["which", "protonvpn"]
      whichProcess.running = true
    }
    if (!pacmanProcess.running) {
      pacmanProcess.command = ["pacman", "-Q", "proton-vpn-gtk-app"]
      pacmanProcess.running = true
    }
  }

  // Omarchy's own installer flow: a floating terminal owns the password prompt,
  // so the shell process never touches privileges.
  function installCli() {
    if (installed || installing) return
    installing = true
    lastError = ""
    Quickshell.execDetached(["omarchy-install-app", "Proton VPN CLI", "proton-vpn-cli"])
    installWatch.restart()
  }

  function watchLink() {
    if (watchProcess.running) return
    _watchStartedMs = Date.now()
    watchProcess.command = ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show", "--active"]
    watchProcess.running = true

    // Proton's own file watch can go stale: if the CLI/app rewrote
    // settings.json (say, adding the `features` block on a first connect)
    // before this plugin ever read one, or the rewrite happened between two
    // inotify events, protonSettings is left stuck null with nothing left to
    // trigger a re-read. Piggyback this same periodic tick to retry, so the
    // Split tunneling row heals itself in a few seconds instead of needing a
    // shell restart.
    if (!protonSettings) protonFile.reload()
  }

  function refreshStatus() {
    if (!installed) return
    if (cliBusy) { _wantStatus = true; return }
    _probeRunning = true
    statusProcess.command = ["protonvpn", "status"]
    statusProcess.running = true
  }

  function refreshAccount() {
    if (!installed) return
    if (cliBusy) { _wantAccount = true; return }
    _probeRunning = true
    accountProcess.command = ["protonvpn", "info"]
    accountProcess.running = true
  }

  function loadCountries(force) {
    if (!installed || !signedIn) return
    if (countriesLoaded && force !== true) return
    if (cliBusy) { _wantCountries = true; return }
    _probeRunning = true
    countriesProcess.command = ["protonvpn", "countries", "list"]
    countriesProcess.running = true
  }

  function loadConfig() {
    // Nothing left to wait for, and no re-read coming to clear it.
    if (!installed || !signedIn) { configPending = ""; configPendingValue = ""; return }
    if (cliBusy) { _wantConfig = true; return }
    _probeRunning = true
    configProcess.command = ["protonvpn", "config", "list"]
    configProcess.running = true
  }

  // Both key and value must be in configValues; anything else is dropped.
  //
  // Refuses while a change is still settling, so a second click (or an Enter
  // from the keyboard cursor, which doesn't go through the row's `enabled`)
  // can't send a contradicting `config set` at a value the panel hasn't been
  // told about yet.
  function setConfig(key, value) {
    if (configPending !== "" || setConfigProcess.running) return
    applyConfig(key, value)
  }

  // The set itself, without the in-flight guard, so the NetShield step-down
  // below can hand off from one failed attempt straight into the next.
  function applyConfig(key, value) {
    var allowed = configValues[key]
    if (!allowed || allowed.indexOf(value) === -1) return
    if (!installed || !signedIn) return
    _configKey = key
    _configValue = value
    configPending = key
    configPendingValue = value
    lastError = ""
    setConfigProcess.command = ["protonvpn", "config", "set", key, value]
    setConfigProcess.running = true
  }

  // ── Split tunneling ─────────────────────────────────────────────────────
  // Proton has no CLI command for this, so the widget edits Proton's own
  // settings file. That is the only file we write that isn't ours, so the
  // rules are strict: read it fresh, change nothing outside
  // `features.split_tunneling`, hand every other key back exactly as found,
  // and never create the file. A missing or unreadable file means Proton
  // has not run here yet, and we say so rather than invent one.
  //
  // Nothing pushes the file at the daemon on its own. The connector reads it
  // whenever it starts, so the `protonvpn status` we already run is what
  // applies a change to a live tunnel; with the tunnel down it lands on the
  // next connect either way.
  //
  // Two limits come from Proton, not from us. Split tunneling is skipped
  // entirely while the kill switch is on, and an app that was already
  // running when the tunnel came up keeps using it until it restarts,
  // because sockets are marked as they are created.
  readonly property string protonSettingsPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
    + "/Proton/VPN/settings.json"

  // The whole parsed file, or null when there isn't a readable one.
  property var protonSettings: null
  property bool splitLoaded: false
  property string splitError: ""

  readonly property bool splitAvailable: splitLoaded && protonSettings !== null
  // Blocked until the CLI has told us the kill switch is off, not merely
  // until it has told us it is on: an unread config is not permission to
  // write, and the row would otherwise be live for the second before the
  // first `config list` lands.
  readonly property bool splitBlocked: !configLoaded || killSwitchOn
  readonly property bool splitOn: splitAvailable && splitSection()["enabled"] === true
  // Whether split tunneling is actually in force, which is not the same as
  // the flag in the file. With the kill switch on, Proton ignores the setting
  // entirely, and a switch sitting in the on position while nothing is being
  // split is the panel telling a comfortable lie. The setting itself is left
  // alone, so turning the kill switch back off brings it back with its apps.
  readonly property bool splitActive: splitAvailable && splitOn && !splitBlocked
  readonly property string splitMode: {
    var m = String(splitSection()["mode"] || "exclude")
    return m === "include" ? "include" : "exclude"
  }
  // App paths for the mode in force. Proton keeps a separate list per mode
  // and remembers both, so switching modes doesn't discard the other one.
  readonly property var splitApps: splitAppsFor(splitMode)

  function readProtonSettings(text) {
    var data = null
    try { data = JSON.parse(text) } catch (e) { data = null }
    // Unparsable is treated exactly like missing: we don't rewrite a file we
    // couldn't read, because that would throw away whatever is in it.
    protonSettings = (data && typeof data === "object" && data["features"]) ? data : null
    splitLoaded = true
  }

  function splitSection() {
    if (!protonSettings) return ({})
    var f = protonSettings["features"]
    var st = f ? f["split_tunneling"] : null
    return st ? st : ({})
  }

  function splitAppsFor(mode) {
    var byMode = splitSection()["config_by_mode"]
    var cfg = byMode ? byMode[mode] : null
    var paths = cfg ? cfg["app_paths"] : null
    if (!paths || typeof paths.length !== "number") return []
    var out = []
    for (var i = 0; i < paths.length; i++) out.push(String(paths[i]))
    return out
  }

  // What the Split tunneling row says under its label. Here rather than in
  // the panel because every branch of it is a state this file owns, the same
  // way configPendingLabel() is.
  function splitDescription() {
    if (!splitLoaded) return "Loading…"
    if (!splitAvailable) return "Sign in and connect once first"
    if (!configLoaded) return "Loading…"
    // One sentence for both cases: nothing "pauses" any more, so nothing
    // should hint that it will come back on its own.
    if (splitBlocked) return "Turn the Kill Switch off to use this"
    if (splitError !== "") return splitError
    if (!splitOn) return "Keep chosen apps off the VPN"
    var n = splitApps.length
    if (n === 0) return "No apps chosen yet"
    if (splitMode === "include")
      return n === 1 ? "Only 1 app uses the VPN" : "Only " + n + " apps use the VPN"
    return n === 1 ? "1 app skips the VPN" : n + " apps skip the VPN"
  }

  function applySplitSettings() {
    // Only a running connector reads the file, so this is what makes a
    // change take hold now instead of at the next connect.
    if (linkActive) refreshStatus()
  }

  // Every split tunneling change funnels through here, so the read-modify-
  // write rules live in exactly one place.
  //
  // `mutate` receives the current `features.split_tunneling` object and
  // changes it in place. Everything else in the file is whatever the last
  // read produced, untouched.
  // `evenWhenBlocked` is only for turning split tunneling off. Turning it on
  // while the kill switch is on would write a setting Proton ignores, but
  // turning it off is always honest, and is how the file is kept in step with
  // what the panel has been showing.
  function writeSplit(mutate, evenWhenBlocked) {
    if (!splitAvailable) return false
    // Proton ignores split tunneling entirely while the kill switch is on, so
    // a write then would be a setting that reads as live and does nothing.
    // Checked here rather than per caller, because the panel's rows are not
    // the only way in: the keyboard cursor calls these functions directly.
    if (splitBlocked && evenWhenBlocked !== true) return false
    // The CLI rewrites this same file, so never write across one of its runs.
    if (busy || setConfigProcess.running || configPending !== "") return false

    var raw = protonFile.text()
    var data = null
    try { data = JSON.parse(raw) } catch (e) { data = null }
    if (!data || typeof data !== "object" || !data["features"]) {
      splitError = "Could not read Proton's settings"
      return false
    }

    var st = data["features"]["split_tunneling"]
    if (!st || typeof st !== "object") {
      splitError = "Could not read Proton's settings"
      return false
    }
    if (!st["config_by_mode"]) {
      st["config_by_mode"] = {
        "exclude": { "mode": "exclude", "app_paths": [], "ip_ranges": [] },
        "include": { "mode": "include", "app_paths": [], "ip_ranges": [] }
      }
    }

    mutate(st)
    splitError = ""
    // Proton writes this file with an indent of 4; match it so a diff after
    // one of our writes shows the one section that changed and nothing else.
    protonFile.setText(JSON.stringify(data, null, 4))
    protonSettings = data
    applySplitSettings()
    return true
  }

  function toggleSplitTunnel() {
    var on = !splitOn
    writeSplit(function(st) { st["enabled"] = on })
  }

  function setSplitMode(mode) {
    if (mode !== "exclude" && mode !== "include") return
    if (mode === splitMode) return
    writeSplit(function(st) { st["mode"] = mode })
  }

  // The panel hands back the full selection rather than one add or remove,
  // which is what MultiSelect emits and what settings.json stores anyway.
  //
  // Paths are only ever accepted from the installed-app scan, so a path that
  // isn't absolute never reaches the file. Anything else is dropped rather
  // than repaired: this is Proton's file, and a guess about what someone
  // meant is worse than ignoring it.
  function setSplitApps(paths) {
    var clean = []
    var seen = ({})
    var arr = (paths && typeof paths.length === "number") ? paths : []
    for (var i = 0; i < arr.length; i++) {
      var p = String(arr[i])
      if (p.charAt(0) !== "/" || p.indexOf("\u0000") !== -1) continue
      if (seen[p]) continue
      seen[p] = true
      clean.push(p)
    }
    var mode = splitMode
    writeSplit(function(st) { st["config_by_mode"][mode]["app_paths"] = clean })
  }

  // Proton refuses a kill switch change while a tunnel is up: `config set
  // kill-switch` answers "Disconnect before changing Kill Switch". A switch
  // you can only use while disconnected isn't a switch, and Always On makes
  // it worse, since disconnecting by hand is undone within a few seconds.
  //
  // So a click while connected does the whole thing: drop the tunnel, change
  // the setting, put the tunnel back where it was. Always On is held off
  // across it, otherwise it would reconnect into the middle and the change
  // would fail exactly the way it does by hand.
  property bool _ksCycle: false
  property string _ksValue: ""
  property var _ksReturn: null

  function toggleKillSwitch() {
    // The mirror of the check in writeSplit(): Proton ignores split tunneling
    // whenever the kill switch is on, so the two are mutually exclusive and
    // each one locks the other. Here rather than on the row, because the
    // keyboard cursor calls this directly and never sees `enabled`.
    if (splitActive) return
    var value = killSwitchOn ? "off" : "standard"

    // For as long as the kill switch has been on, the panel has shown split
    // tunneling as off, because Proton was ignoring it. The flag in Proton's
    // file can still say otherwise, and turning the kill switch off would
    // then bring split tunneling back on its own, which reads as a switch
    // flipping itself. So make the file agree with what the panel has been
    // saying. Both app lists are untouched, so one click puts it back.
    if (value === "off" && splitOn) {
      writeSplit(function(st) { st["enabled"] = false }, true)
    }
    // Nothing to work around while the tunnel is down: one CLI call, as before.
    if (!connected && !linkActive) { setConfig("kill-switch", value); return }
    if (_ksCycle || configPending !== "" || busy) return

    _ksCycle = true
    _ksValue = value
    // Back to where we are now, rather than to whatever Fastest picks later.
    _ksReturn = (recents.length > 0 && Array.isArray(recents[0].args)) ? recents[0] : null
    // The row says "Turning off…" from the first click to the last step, the
    // same words the one-call path uses. From the outside this is one change
    // that takes longer, not three things happening to you.
    configPending = "kill-switch"
    configPendingValue = value
    disconnect()
  }

  // Called when the tunnel is down and the setting has been written, whether
  // or not it succeeded: leaving someone disconnected because their kill
  // switch change failed would be the worse half of a bad trade.
  function ksCycleFinish() {
    _ksCycle = false
    var target = _ksReturn
    _ksReturn = null
    // Starting a connect clears lastError, so a failed setting's message has
    // to be carried across it. The tunnel coming back up is not evidence the
    // change worked, and that is exactly when someone needs to be told.
    var carried = lastError
    if (target) connectTo(target.args, "Reconnecting to " + target.title + "…", target, false)
    else connectTo([], "Reconnecting to fastest…", null, false)
    if (carried !== "") lastError = carried
  }
  // Full protection first; the CLI refuses ads/trackers on a free plan and
  // the retry below steps down to malware-only.
  function toggleNetShield() { setConfig("netshield", netShieldOn ? "off" : "malware-ads-trackers") }
  function togglePortForwarding() { setConfig("port-forwarding", portForwardingOn ? "off" : "on") }

  function dismissNudge() {
    nudgeDismissed = true
    saveState()
  }

  function toggle() {
    if (!installed || busy) return
    // A live tunnel is proof of a session, so never send an already-signed-in
    // user to a sign-in prompt just because the account probe is stale or
    // briefly failed. Only offer sign-in once we've probed AND there's no link.
    if (!signedIn && !connected) {
      if (accountProbed) signIn("")
      else refreshAccount()
      return
    }
    if (connected) disconnect()
    else connectTo([], "Connecting to fastest…", null)
  }

  // target: {key, title, subtitle, args} recorded to recents on success, or
  // null for quick actions that are already one click away.
  // Whether the current connection was asked for with the P2P row: most
  // servers permit P2P, so the panel only headlines it when that's what you
  // clicked. Not persisted; after a restart the header shows the name.
  property bool p2pRequested: false
  readonly property bool currentP2p: !!(currentPlace && currentPlace.p2p === true)

  function connectTo(args, label, target, auto) {
    if (!installed || !signedIn || busy) return
    p2pRequested = args.indexOf("--p2p") !== -1
    _autoAttempt = auto === true
    _desired = 1
    _expectDown = false
    _target = target
    pendingLabel = label || "Connecting…"
    actionStatus = pendingLabel
    lastError = ""
    connectProcess.command = ["protonvpn", "connect"].concat(args || [])
    connectProcess.running = true
  }

  function connectFastest() { connectTo([], "Connecting to fastest…", null) }
  function connectRandom() { connectTo(["--random"], "Connecting to a random server…", null) }
  function connectP2P() { connectTo(["--p2p"], "Connecting to fastest P2P…", null) }
  function connectSecureCore() { connectTo(["--securecore"], "Connecting via Secure Core…", null) }
  function connectTor() { connectTo(["--tor"], "Connecting via Tor…", null) }

  function connectCountry(code, name) {
    var c = String(code || "").trim().toUpperCase()
    if (!/^[A-Z]{2}$/.test(c)) return
    var title = name || c
    connectTo(["--country", c], "Connecting to " + title + "…",
              { key: "country:" + c, title: title, subtitle: "Fastest server", args: ["--country", c] })
  }

  // `protonvpn connect <NAME>` takes precedence over every filter in the CLI's
  // own selection, so a named server connects exactly as asked. City and
  // country are only for the label people see.
  function connectServer(name, city, countryName) {
    var n = String(name || "").trim()
    // A name, never a flag: connectArg allows a leading dash for `--country`.
    if (!connectArg.test(n) || n.charAt(0) === "-") return
    var title = city || n
    var subtitle = [countryName, n].filter(function(s) { return s }).join(" · ")
    connectTo([n], "Connecting to " + title + "…",
              { key: "server:" + n, title: title, subtitle: subtitle, args: [n] })
  }

  function connectRecent(index) {
    var r = recents[index]
    if (!r || !Array.isArray(r.args)) return
    connectTo(r.args, "Connecting to " + r.title + "…", r)
  }

  function loadServers(code, name) {
    var c = String(code || "").trim().toUpperCase()
    if (!installed || !/^[A-Z]{2}$/.test(c) || serversProcess.running) return
    serversCountry = c
    serversCountryName = name || c
    servers = []
    serversLoading = true
    serversProcess.command = ["python3", scriptPath, c, "80"]
    serversProcess.running = true
  }

  function loadCities(force) {
    if (!installed || citiesProcess.running) return
    if (citiesLoaded && force !== true) return
    citiesProcess.command = ["python3", scriptPath, "--cities"]
    citiesProcess.running = true
  }

  // Which city the connected server is in. Runs whenever the server name
  // changes; a lookup arriving mid-run is queued, not dropped.
  function locateServer(name) {
    var n = String(name || "").trim()
    if (n === "") { currentPlace = null; _locatePending = ""; return }
    if (currentPlace && currentPlace.name === n) return
    if (locateProcess.running) { _locatePending = n; return }
    locateProcess.command = ["python3", scriptPath, "--locate", n]
    locateProcess.running = true
  }

  onDisplayServerChanged: {
    locateServer(displayServer)
    // A different server means a different port, or none.
    forwardedPort = ""
  }

  function countryName(code) {
    var c = String(code || "").toUpperCase()
    for (var i = 0; i < countries.length; i++) if (countries[i].code === c) return countries[i].name
    return c
  }

  function clearServers() {
    servers = []
    serversCountry = ""
    serversCountryName = ""
    serversLoading = false
  }

  function disconnect() {
    if (!installed || busy) return
    _desired = 0
    _expectDown = true
    trafficReset()
    pendingLabel = "Disconnecting…"
    actionStatus = ""
    lastError = ""
    actionProcess.command = ["protonvpn", "disconnect"]
    actionProcess.running = true
  }

  // Sign-in is interactive (password, then a TOTP token), so it has to happen
  // in a real terminal, the CLI only accepts them from a tty. The username
  // can be typed in the panel; with none given the terminal asks for it.
  function signIn(username) {
    var u = String(username || "").trim()
    var cmd
    if (u === "") {
      cmd = "read -rp 'Proton username: ' u && protonvpn signin \"$u\""
    } else if (Model.validUsername(u)) {
      cmd = "protonvpn signin " + Model.shellQuote(u)
    } else {
      lastError = "Usernames can only contain letters, numbers and . _ + @ -"
      return false
    }
    lastError = ""
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", cmd])
    signInWatch.restart()
    return true
  }

  function signOut() {
    if (!installed || busy) return
    _desired = 0
    _expectDown = true
    trafficReset()
    pendingLabel = "Signing out…"
    actionProcess.command = ["protonvpn", "signout"]
    actionProcess.running = true
  }

  function trafficReset() {
    rxHistory = []; txHistory = []
    rxRate = 0; txRate = 0
    sessionRx = 0; sessionTx = 0
    uptimeSec = 0
    _lastRx = -1; _lastTx = -1; _lastSampleMs = 0
    _linkUpMs = Date.now()
  }

  // sysfs files report a size of 0, so FileView reads them as empty; `cat`
  // reads until EOF and costs about a millisecond once a second.
  function trafficSample() {
    if (trafficProcess.running || linkDevice === "") return
    var base = "/sys/class/net/" + linkDevice + "/statistics/"
    trafficProcess.command = ["cat", base + "rx_bytes", base + "tx_bytes"]
    trafficProcess.running = true
  }

  function trafficApply(text) {
    var parts = String(text || "").trim().split(/\s+/)
    var rx = parseFloat(parts[0]), tx = parseFloat(parts[1])
    if (!isFinite(rx) || !isFinite(tx)) return
    var now = Date.now()
    if (_lastRx >= 0 && _lastSampleMs > 0) {
      var dt = Math.max(0.25, (now - _lastSampleMs) / 1000)
      var drx = Math.max(0, rx - _lastRx), dtx = Math.max(0, tx - _lastTx)
      rxRate = drx / dt; txRate = dtx / dt
      sessionRx += drx; sessionTx += dtx
      var h = rxHistory.slice(); h.push(rxRate); if (h.length > trafficSamples) h.shift(); rxHistory = h
      var g = txHistory.slice(); g.push(txRate); if (g.length > trafficSamples) g.shift(); txHistory = g
    }
    _lastRx = rx; _lastTx = tx; _lastSampleMs = now
    uptimeSec = _linkUpMs > 0 ? Math.floor((now - _linkUpMs) / 1000) : 0
  }

  // The plugin's own mark for the toast, written to the state dir in the
  // theme's accent colour so it wears every Omarchy theme like the widget
  // does, and rewritten whenever the theme changes. A themed-icon name was
  // the wrong tool here: most icon themes don't carry `network-vpn`, and
  // the shell drew Qt's missing-texture checkerboard in its place (#21).
  readonly property string notificationIconPath: stateDir + "/notification-icon.svg"
  readonly property string protonMarkPath: "m10.176 20.058.858-1.28 6.513-9.838c.57-.86.026-2.014-1.005-2.131L.378 4.95l8.373 15.055a.84.84 0 0 0 1.424.052h.001zM23.586 7.14l-9.662 14.61c-1.036 1.567-3.38 1.478-4.293-.162l-.093-.168c.3-.01.594-.086.855-.235a1.85 1.85 0 0 0 .612-.57l.86-1.28 6.516-9.844c.46-.694.525-1.56.173-2.314a2.375 2.375 0 0 0-1.899-1.364L.493 3.956l-.476-.054C-.163 2.392 1.101.95 2.784 1.143l18.991 2.16c1.856.21 2.835 2.289 1.812 3.838z"

  function writeNotificationIcon() {
    // Qt prints an opaque colour as #rrggbb and a translucent one as
    // #aarrggbb; SVG wants the former, so drop the alpha if present.
    var hex = String(Color.accent)
    if (hex.length === 9) hex = "#" + hex.slice(3)
    notificationIconFile.setText('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
                                 + '<path fill="' + hex + '" d="' + protonMarkPath + '"/></svg>\n')
  }

  function notify(summary, body, urgency) {
    if (!notificationsOn) return
    // The panel already shows the state change in its header and map, so a
    // toast on top of it is noise. Only notify when the panel isn't open.
    if (panelOpen) return
    // Call org.freedesktop.Notifications.Notify directly instead of going
    // through notify-send or the omarchy-notification-send wrapper: one
    // process, no argv reparsing of the summary/body, and the omarchy-glyph
    // hint gives the shell a Nerd Font shield-lock to draw if the SVG isn't
    // there yet (first launch) or fails to load. Signature: app_name, replaces_id, app_icon, summary,
    // body, actions, hints, expire_timeout.
    var level = urgency === "critical" ? "2" : (urgency === "low" ? "0" : "1")
    Quickshell.execDetached(["busctl", "--user", "--", "call",
                             "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                             "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
                             "OmaProton VPN", "0", notificationIconPath, summary, Model.escapeMarkup(body),
                             "0",
                             "2", "urgency", "y", level, "omarchy-glyph", "s", "\udb82\udd9d",
                             "-1"])
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    statusConnected = parsed.connected
    statusConnecting = parsed.connecting
    statusText = parsed.statusText
    serverName = parsed.serverName
    location = parsed.location
    fields = parsed.fields
    reconcile()
  }

  // Drop the optimistic override as soon as the world agrees with it, and
  // also once the action that set it has finished, whatever the outcome.
  //
  // That second condition is not belt-and-braces. The override says "ignore
  // reality, this is where we're heading", and it used to be released only on
  // agreement. Always On can bring the tunnel straight back up as a
  // disconnect completes, so reality settles on the opposite of what was
  // asked, the two never agree, and the override latches for the rest of the
  // session: the panel reads "Not protected" over a live tunnel and the power
  // button starts connecting instead of disconnecting.
  //
  // Both callers run this against freshly polled state (nmcli in the link
  // watcher, `protonvpn status` in applyStatus), so releasing on !busy hands
  // the UI back to an observation, never to a stale one.
  // Drop the optimistic override as soon as the world agrees with it.
  //
  // It deliberately does NOT release while reality disagrees: during a connect
  // the link poll can still be reporting the old state, and releasing on that
  // flashes "Not protected" over a connect that is succeeding.
  function reconcile() {
    if (_desired === -1) return
    var real = linkActive || statusConnected
    if (real === (_desired === 1)) {
      _desired = -1
      pendingLabel = ""
      return
    }
    // Safety valve only, never part of a normal connect or disconnect. If the
    // world settles on the opposite of what was asked and stays there, the
    // override would otherwise hold the panel at a lie for the rest of the
    // session (a disconnect that something else immediately undoes leaves
    // "Not protected" over a live tunnel, and the power button then tries to
    // connect). Fifteen seconds is far longer than the few seconds a real
    // connect needs to settle, so this can never cause a flash.
    if (!busy && _actionEndedMs > 0 && Date.now() - _actionEndedMs > 15000) {
      _desired = -1
      pendingLabel = ""
    }
  }


  // The only argv a recent may carry: `--country US`, `--p2p`, or a server
  // name like US-TX#572. The state file is plain JSON under $HOME, so it is
  // checked on the way in rather than trusted on the way to `protonvpn
  // connect`. Anything that doesn't fit is dropped, not repaired.
  readonly property var connectArg: /^[A-Za-z0-9#-]{1,64}$/

  function cleanRecent(r) {
    if (!r || typeof r !== "object" || typeof r.key !== "string" || !Array.isArray(r.args)) return null
    var args = []
    for (var i = 0; i < r.args.length && i < 4; i++) {
      var a = String(r.args[i])
      if (!connectArg.test(a)) return null
      args.push(a)
    }
    return { key: r.key, title: String(r.title || ""), subtitle: String(r.subtitle || ""), args: args }
  }

  function applyState(text) {
    try {
      var s = JSON.parse(String(text || "{}"))
      recents = Array.isArray(s.recents) ? s.recents.slice(0, 3).map(cleanRecent).filter(Boolean) : []
      nudgeDismissed = s.killSwitchNudgeDismissed === true
      autoConnect = s.autoConnect === true
    } catch (e) {
      recents = []
      nudgeDismissed = false
      autoConnect = false
    }
    stateLoaded = true
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      recents: recents,
      killSwitchNudgeDismissed: nudgeDismissed,
      autoConnect: autoConnect
    }))
  }

  // ── Always On ───────────────────────────────────────────────────────────

  function toggleAutoConnect() {
    autoConnect = !autoConnect
    _autoNextMs = 0
    saveState()
    autoReconcile()
  }

  // Run on every link poll, and checked against the world as it is right now.
  //
  // Back to the top of Recent, which is the server we were last actually on,
  // however we got there. If that one fails it is skipped next time round, so
  // a server that is full or gone can't stall this forever.
  function autoReconcile() {
    if (!autoReady) return
    // The kill switch cycle drops the tunnel on purpose and puts it back
    // itself. Always On stepping in here is what made this impossible to do
    // by hand in the first place.
    if (_ksCycle) return
    if (connected || linkActive || busy) return
    if (_autoNextMs > 0 && Date.now() < _autoNextMs) return
    var t = recents.length > 0 && Array.isArray(recents[0].args) ? recents[0] : null
    if (t && !_autoPinFailed) connectTo(t.args, "Reconnecting to " + t.title + "…", t, true)
    else connectTo([], "Reconnecting to fastest…", null, true)
  }

  function recordRecent(target) {
    if (!target || !target.key) return
    var next = [target]
    for (var i = 0; i < recents.length && next.length < 3; i++) {
      if (recents[i] && recents[i].key !== target.key) next.push(recents[i])
    }
    recents = next
    saveState()
  }

  Component.onCompleted: {
    // Owner-only, and fixed up on existing installs too: the file holds where
    // you've been connecting, which is nobody else's business on a shared box.
    Quickshell.execDetached(["install", "-d", "-m", "700", stateDir])
    refresh()
  }

  // The state dir is created by a detached process, so the icon is written
  // a moment later rather than racing it on a first launch.
  Timer {
    interval: 1000
    running: true
    repeat: false
    onTriggered: root.writeNotificationIcon()
  }

  Connections {
    target: Color
    function onAccentChanged() { root.writeNotificationIcon() }
  }

  onPanelOpenChanged: if (panelOpen) {
    refresh()
    loadCountries(false)
    loadConfig()
  }

  Process {
    id: trafficProcess
    running: false
    command: []
    stdout: StdioCollector { id: trafficStdout; waitForEnd: true }
    onExited: function(exitCode) { if (exitCode === 0) root.trafficApply(String(trafficStdout.text || "")) }
  }

  Timer {
    id: trafficTimer
    interval: 1000
    repeat: true
    running: root.panelOpen && root.linkActive && root.linkDevice !== ""
    triggeredOnStart: true
    onTriggered: root.trafficSample()
  }

  FileView {
    id: notificationIconFile
    path: root.notificationIconPath
    printErrors: false
    atomicWrites: true
  }

  Timer {
    interval: 45000
    repeat: true
    running: root.portWanted
    onTriggered: root.refreshPort()
  }

  Process {
    id: portProcess
    running: false
    command: []
    stdout: StdioCollector { id: portStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var port = ""
      try {
        var out = exitCode === 0 ? JSON.parse(String(portStdout.text || "{}")) : {}
        if (out && out.port) port = String(out.port)
      } catch (e) { port = "" }
      // Digits only, or nothing: this is what goes to the clipboard.
      if (!/^[1-9][0-9]{0,4}$/.test(port)) port = ""
      // A missed renewal (one timeout) shouldn't blank the row for 45 s; a
      // server change already clears it, and no port on a non-P2P server
      // stays "" because nothing ever set it.
      if (port !== "" || !root.portWanted) root.forwardedPort = port
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("{}")
  }

  // Proton's file, not ours. Watched rather than polled, because the CLI
  // rewrites it on every `config set` and the panel would otherwise show a
  // stale copy of a file that just changed underneath it.
  FileView {
    id: protonFile
    path: root.protonSettingsPath
    printErrors: false
    watchChanges: true
    atomicWrites: true
    onLoaded: root.readProtonSettings(text())
    onFileChanged: reload()
    // No file yet, or no permission to read it. Either way there is nothing
    // to edit and the panel says so instead of offering a switch that would
    // have to create it.
    onLoadFailed: { root.protonSettings = null; root.splitLoaded = true }
    onSaveFailed: root.splitError = "Could not save Proton's settings"
  }

  Timer {
    id: watchTimer
    interval: root.watchIntervalSec * 1000
    repeat: true
    running: root.installed
    triggeredOnStart: true
    onTriggered: root.watchLink()
  }

  Timer {
    id: statusTimer
    // Cheap enough to keep current while the panel is open; throttled back to
    // the configured interval once it closes.
    interval: (root.panelOpen ? 5 : root.refreshIntervalSec) * 1000
    repeat: true
    // Not while a connect or disconnect is running: `protonvpn connect`
    // blocks for 30-60s, and a 5s poll across that is where most of the
    // concurrent CLI processes used to come from. delayedRefresh pulls fresh
    // state 1.2s after the action finishes, so nothing is lost by waiting.
    running: root.installed && root.signedIn && !root.busy
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: delayedRefresh
    interval: 1200
    repeat: false
    onTriggered: {
      root.watchLink()
      root.refreshStatus()
    }
  }

  // Start exactly one deferred probe, the moment a slot frees up, so the queue
  // drains at the CLI's own pace rather than waiting on a timer tick.
  // Account first: `signedIn` gates the map, the tabs and every setting.
  function drainProbes() {
    if (cliBusy) return
    if (_wantAccount) { _wantAccount = false; refreshAccount(); return }
    if (_wantConfig) { _wantConfig = false; loadConfig(); return }
    if (_wantCountries) { _wantCountries = false; loadCountries(false); return }
    if (_wantStatus) { _wantStatus = false; refreshStatus(); return }
  }

  // Safety net only: drainProbes() normally runs from each probe's exit.
  Timer {
    id: probeRetry
    interval: 600
    repeat: true
    running: root._probesPending && root.installed
    onTriggered: root.drainProbes()
  }

  Timer {
    id: accountRetry
    interval: 5000
    repeat: false
    onTriggered: root.refreshAccount()
  }

  Timer {
    id: actionStatusTimer
    interval: 6000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  // Sign-in happens out of process in a terminal; poll for a while so the
  // panel flips to the signed-in view on its own.
  Timer {
    id: signInWatch
    interval: 3000
    repeat: true
    triggeredOnStart: false
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refreshAccount()
      if (root.signedIn || ticks > 40) stop()
    }
  }

  // Same idea for the package install: up to five minutes for pacman.
  Timer {
    id: installWatch
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.probeInstalled()
      if (root.installed || ticks > 100) {
        stop()
        root.installing = false
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      var was = root.installed
      root.installed = exitCode === 0
      if (root.installed) {
        if (!was) {
          root.installing = false
          root.lastError = ""
          root.statusText = "Checking…"
        }
        root.refresh()
        root.loadCities(false)
      } else if (!root.installing) {
        root.statusText = "Proton VPN CLI not installed"
      }
    }
  }

  Process {
    id: pacmanProcess
    running: false
    command: []
    onExited: function(exitCode) { root.gtkAppInstalled = exitCode === 0 }
  }

  Process {
    id: watchProcess
    running: false
    command: []
    stdout: StdioCollector { id: watchStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var link = Model.parseActiveVpn(String(watchStdout.text || ""))
      var was = root.linkActive
      root.linkActive = link.active
      root.linkServer = link.server
      root.linkDevice = link.device
      if (link.active && !was) root.trafficReset()
      if (!link.active && was) root.trafficReset()
      // A tunnel we didn't ask to close is the one thing a person must hear
      // about: the icon dimming is not a signal most people read.
      //
      // A connect in flight is not that. Two things take the tunnel down
      // mid-connect and neither is news: switching servers tears the old one
      // down first, and every `protonvpn connect` briefly double-activates,
      // because the CLI adds the NM profile (which NetworkManager then
      // auto-activates on its own, autoconnect defaults to yes) and then
      // explicitly activates it, so NM preempts its own activation. Without
      // this guard that lands as "You're no longer protected" in the middle
      // of a connect the person just asked for.
      if (was && !link.active) {
        if (!root._expectDown && !actionProcess.running && !connectProcess.running)
          root.notify("VPN Disconnected \udb83\udfc6", "You're no longer protected.", "critical")
        root._expectDown = false
      }
      root.reconcile()
      root.autoReconcile()
      // The tunnel came up or went away behind our back (CLI in a terminal,
      // a drop, a reconnect), pull the detail rows back in sync.
      if (was !== link.active) root.refreshStatus()
      // A tunnel we didn't think we were signed in for means the account
      // state is wrong, not the link. Re-probe rather than trusting it.
      if (link.active && !root.signedIn) root.refreshAccount()
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      Qt.callLater(root.drainProbes)
      if (exitCode === 0) {
        root.applyStatus(String(statusStdout.text || ""))
        root.lastError = ""
      } else {
        root.lastError = Model.elide(String(statusStderr.text || "") || "protonvpn status failed")
      }
    }
  }

  Process {
    id: accountProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      Qt.callLater(root.drainProbes)
      // A one-off failure must not latch "signed out" forever, retry instead
      // of leaving a signed-in user staring at a sign-in prompt.
      if (exitCode !== 0) { accountRetry.restart(); return }
      var info = Model.parseAccount(String(accountStdout.text || ""))
      var was = root.signedIn
      root.accountProbed = true
      root.signedIn = info.signedIn
      root.account = info.account
      root.plan = info.plan
      if (info.signedIn && !was) {
        root.loadCountries(true)
        root.loadConfig()
      }
      if (!info.signedIn) {
        root.countries = []
        root.countriesLoaded = false
        root.config = {}
        root.configLoaded = false
      }
    }
  }

  Process {
    id: configProcess
    running: false
    command: []
    stdout: StdioCollector { id: configStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      root.configPending = ""
      root.configPendingValue = ""
      Qt.callLater(root.drainProbes)
      if (exitCode !== 0) return
      root.config = Model.parseConfig(String(configStdout.text || ""))
      root.configLoaded = true
    }
  }

  Process {
    id: setConfigProcess
    running: false
    command: []
    stdout: StdioCollector { id: setConfigStdout; waitForEnd: true }
    stderr: StdioCollector { id: setConfigStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var err = String(setConfigStderr.text || "") || String(setConfigStdout.text || "")
      var key = root._configKey
      var value = root._configValue
      root._configKey = ""
      root._configValue = ""
      if (exitCode !== 0) {
        if (key === "netshield" && value === "malware-ads-trackers" && Model.isPlanError(err)) {
          root.applyConfig("netshield", "malware-only")
          return
        }
        root.lastError = Model.isPlanError(err) ? "Requires a Proton VPN Plus plan" : Model.elide(err || "Setting failed")
      }
      // Last step of a kill switch change: whatever the CLI made of it, the
      // tunnel goes back up. Before loadConfig(), so the re-read queues behind
      // the connect instead of racing it.
      if (root._ksCycle) root.ksCycleFinish()
      root.loadConfig()
    }
  }

  Process {
    id: serversProcess
    running: false
    command: []
    stdout: StdioCollector { id: serversStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.serversLoading = false
      if (exitCode !== 0) { root.servers = []; return }
      try {
        root.servers = JSON.parse(String(serversStdout.text || "[]"))
      } catch (e) {
        root.servers = []
      }
    }
  }

  Process {
    id: citiesProcess
    running: false
    command: []
    stdout: StdioCollector { id: citiesStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var list = JSON.parse(String(citiesStdout.text || "[]"))
        root.cities = Array.isArray(list) ? list : []
        root.citiesLoaded = root.cities.length > 0
      } catch (e) {
        root.cities = []
      }
    }
  }

  Process {
    id: locateProcess
    running: false
    command: []
    stdout: StdioCollector { id: locateStdout; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var place = exitCode === 0 ? JSON.parse(String(locateStdout.text || "{}")) : {}
        root.currentPlace = place && place.lat !== undefined && place.lat !== null ? place : null
      } catch (e) {
        root.currentPlace = null
      }
      if (root._locatePending !== "") {
        var next = root._locatePending
        root._locatePending = ""
        root.locateServer(next)
      }
    }
  }

  Process {
    id: countriesProcess
    running: false
    command: []
    stdout: StdioCollector { id: countriesStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      Qt.callLater(root.drainProbes)
      if (exitCode !== 0) return
      var list = Model.parseCountries(String(countriesStdout.text || ""))
      root.countries = list
      root.countriesLoaded = list.length > 0
    }
  }

  Process {
    id: connectProcess
    running: false
    command: []
    stdout: StdioCollector { id: connectStdout; waitForEnd: true }
    stderr: StdioCollector { id: connectStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._actionEndedMs = Date.now()
      var out = String(connectStdout.text || "")
      var err = String(connectStderr.text || "")
      var target = root._target
      var wasAuto = root._autoAttempt
      root._target = null
      root._autoAttempt = false
      root.pendingLabel = ""
      root._autoNextMs = wasAuto && exitCode !== 0 ? Date.now() + root.autoRetryMs : 0
      if (exitCode === 0) root._autoPinFailed = false
      else if (wasAuto) root._autoPinFailed = true
      if (exitCode !== 0) {
        root._desired = -1
        var text = err || out || "Connect failed"
        root.lastError = Model.isPlanError(text) ? "Requires a Proton VPN Plus plan" : Model.elide(text)
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        // The confirmation line, which is not always the first one: an expired
        // server list puts "Server list is outdated, updating..." ahead of it,
        // and that is not what the panel or the notification should report.
        var line = Model.elide(Model.connectedLine(out) || out.split("\n")[0] || "", 90)
        root.actionStatus = line
        actionStatusTimer.restart()
        // Fastest, Random, P2P, Secure Core and Tor arrive here with no target
        // because you didn't name a destination, but you still ended up
        // somewhere. Recover it from the CLI's own confirmation line so Recent
        // is a record of where you've been, not only of what you clicked.
        if (!target) {
          var landed = Model.parseConnected(out)
          if (landed) target = {
            key: "server:" + landed.name,
            title: landed.city !== "" ? landed.city : landed.name,
            subtitle: [landed.country, landed.name].filter(function(v) { return v !== "" }).join(" · "),
            args: [landed.name]
          }
        }
        root.recordRecent(target)
        // "Connected to NL#42 in Amsterdam, Netherlands." -> the server, plus
        // the protocol the CLI is configured for, since its confirmation
        // line never names it and `protonvpn status` hasn't run yet.
        var where = line.replace(/^connected to\s+/i, "").replace(/\.\s*$/, "")
        var proto = Model.protocolLabel(root.protonSettings ? root.protonSettings["protocol"] : "")
        root.notify("VPN Connected \udb80\udf3e", [where, proto].filter(function(v) { return v !== "" }).join(" · "), "normal")
        root.loadCities(true)
      }
      // Look at the link now rather than waiting up to watchIntervalSec, so
      // the override is released against fresh data as soon as possible.
      root.watchLink()
      delayedRefresh.restart()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._actionEndedMs = Date.now()
      var out = String(actionStdout.text || "")
      var err = String(actionStderr.text || "")
      root.pendingLabel = ""
      if (exitCode !== 0) {
        root._desired = -1
        root._expectDown = false
        root.lastError = Model.elide(err || out || "Command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      // Second step of a kill switch change: the tunnel is down, which is the
      // only state the CLI will accept the setting in. A failed disconnect
      // means the tunnel is still up, so there is nothing to try and the row
      // goes back to what the CLI last reported.
      if (root._ksCycle) {
        if (exitCode !== 0) {
          root._ksCycle = false
          root._ksReturn = null
          root.configPending = ""
          root.configPendingValue = ""
        } else {
          root.applyConfig("kill-switch", root._ksValue)
        }
      }

      root.refreshAccount()
      delayedRefresh.restart()
    }
  }
}
