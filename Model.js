// Parsing helpers for the Proton VPN CLI's human-readable output.
//
// The CLI has no --json anywhere, so every parser here is deliberately
// tolerant: unknown lines are skipped rather than treated as errors, and the
// detail rows are rendered from whatever key/value pairs `protonvpn status`
// happens to print. A future CLI release that adds or renames a field shows
// up as a new row instead of a broken widget.

function stripAnsi(text) {
  return String(text || "").replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, "")
}

// "Label: value" lines -> ordered list plus a lowercased lookup map.
// Guards against prose (long labels, column-aligned table rows) being
// mistaken for fields.
function parseKeyValues(raw) {
  var out = { order: [], map: {} }
  var lines = stripAnsi(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    var idx = line.indexOf(":")
    if (idx <= 0) continue
    var label = line.substring(0, idx).trim()
    var value = line.substring(idx + 1).trim()
    if (label === "" || value === "") continue
    if (label.length > 28) continue
    if (/\s{2,}/.test(label)) continue
    out.order.push({ label: label, value: value })
    out.map[label.toLowerCase()] = value
  }
  return out
}

// "NL#42 in Amsterdam, Netherlands" -> "NL#42"
function serverName(server) {
  var s = String(server || "").trim()
  if (s === "") return ""
  var m = s.match(/^(\S+)\s+in\s+(.+)$/)
  return m ? m[1] : s
}

// "NL#42 in Amsterdam, Netherlands" -> "Amsterdam, Netherlands"
function serverLocation(server) {
  var s = String(server || "").trim()
  if (s === "") return ""
  var m = s.match(/^(\S+)\s+in\s+(.+)$/)
  return m ? m[2] : ""
}

// `protonvpn status`
//
//   Status: Connected
//   Server: NL#42 in Amsterdam, Netherlands
//   Load: 21%
//   Protocol: wireguard
//
// Signed out or idle it prints only "Status: Disconnected".
function parseStatus(raw) {
  var kv = parseKeyValues(raw)
  var statusValue = kv.map["status"] || ""
  // "Disconnected" contains "connect", so anchor both tests at the start.
  var connected = /^connected/i.test(statusValue)
  var connecting = /^connecting/i.test(statusValue)
  var server = kv.map["server"] || ""

  var fields = []
  for (var i = 0; i < kv.order.length; i++) {
    var key = kv.order[i].label.toLowerCase()
    // Status and server already headline the hero, don't repeat them.
    if (key === "status" || key === "server") continue
    fields.push(kv.order[i])
  }

  return {
    ok: true,
    connected: connected,
    connecting: connecting,
    statusText: statusValue !== "" ? statusValue : "Unknown",
    server: server,
    serverName: serverName(server),
    location: serverLocation(server),
    fields: fields
  }
}

// True when `raw` carries a whole answer from `protonvpn status`: a Status
// line whose value is one of the words the CLI prints. Tells a run that
// answered and then died on its way out from one that never answered.
function statusComplete(raw) {
  var v = parseKeyValues(raw).map["status"] || ""
  return /^(connected|connecting|disconnected)$/i.test(v)
}

// "CH-US#3", "IS-JP#1", "SE-FR#2": only CH, IS and SE are entry countries.
function isSecureCore(name) {
  return /^(CH|IS|SE)-[A-Z]{2}/i.test(String(name || "").trim())
}

// Secure Core servers are named for both hops: "CH-US#3" enters Switzerland
// and exits US server 3. Show that as a route, "CH → US#3". Only CH, IS and
// SE are entry countries, which keeps regional names like "US-TX#40" as-is.
function routeLabel(name) {
  var n = String(name || "").trim()
  var m = n.match(/^(CH|IS|SE)-([A-Z]{2}(?:-[A-Z]{2,3})?)#(\d+)$/i)
  if (!m) return n
  return m[1].toUpperCase() + " → " + m[2].toUpperCase() + "#" + m[3]
}

// settings.json `protocol` -> a label for the panel and notifications.
function protocolLabel(raw) {
  var p = String(raw || "").trim().toLowerCase()
  if (p === "") return ""
  if (p === "wireguard") return "WireGuard"
  if (p === "openvpn-udp" || p === "openvpn_udp") return "OpenVPN UDP"
  if (p === "openvpn-tcp" || p === "openvpn_tcp") return "OpenVPN TCP"
  if (p.indexOf("openvpn") === 0) return "OpenVPN"
  // Anything else is shown only if it looks like a protocol name.
  if (!/^[a-z0-9_-]{1,32}$/.test(p)) return ""
  return p.charAt(0).toUpperCase() + p.slice(1)
}

// Notification bodies are rendered as markup by the shell, so text that came
// from the CLI is escaped before it goes into one.
function escapeMarkup(s) {
  return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// `protonvpn info` -> "Account: 'user@example.com'", or "Account: 'None'"
// while signed out.
function parseAccount(raw) {
  var kv = parseKeyValues(raw)
  var account = String(kv.map["account"] || "").replace(/^['"]|['"]$/g, "").trim()
  var plan = String(kv.map["plan"] || "").replace(/^['"]|['"]$/g, "").trim()
  var signedIn = account !== "" && account.toLowerCase() !== "none"
  return {
    signedIn: signedIn,
    account: signedIn ? account : "",
    plan: signedIn ? plan : ""
  }
}

// `protonvpn countries list` -> a two-column table:
//
//   Country                           Code
//   --------------------------------  ------
//   Afghanistan                       AF
//
// Rows are "name<2+ spaces>CODE"; the header and rule are skipped by shape.
function parseCountries(raw) {
  var lines = stripAnsi(raw).split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\s+$/, "")
    if (line.trim() === "") continue
    if (/^[-+=|\s]+$/.test(line)) continue
    var m = line.match(/^\s*(.+?)\s{2,}([A-Za-z]{2})$/)
    if (!m) continue
    var name = m[1].trim()
    var code = m[2].toUpperCase()
    if (name === "" || name.toLowerCase() === "country") continue
    out.push({ name: name, code: code })
  }
  return out
}

// `nmcli -t -f NAME,TYPE,DEVICE,STATE connection show --active`
//
// The Proton CLI brings its tunnel up on device `proton0` as a `wireguard`
// connection (or a `vpn`/`tun` one for OpenVPN), named "ProtonVPN <server>".
// Only the device and the type decide whether it's a tunnel: a connection
// name is user-chosen, so an ordinary Wi-Fi profile called "ProtonVPN x"
// must never make the widget claim you're protected. The name is used for
// the server label alone. Proton's IPv6 leak-guard ("pvpn-killswitch-ipv6"
// on a dummy device) stays active independently and is not a tunnel either.
//
// NAME can itself contain a colon, so fields are taken from the right.
var TUNNEL_DEVICE = /^proton\d*$/i
var TUNNEL_TYPES = { "wireguard": true, "vpn": true, "tun": true }

function parseActiveVpn(raw) {
  var lines = stripAnsi(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    var parts = line.split(":")
    if (parts.length < 4) continue
    var state = parts[parts.length - 1]
    var device = parts[parts.length - 2]
    var type = parts[parts.length - 3]
    var name = parts.slice(0, parts.length - 3).join(":")
    if (!/^activated$/i.test(state)) continue
    if (!TUNNEL_DEVICE.test(device)) continue
    if (!TUNNEL_TYPES[String(type).toLowerCase()]) continue
    return {
      active: true,
      name: name,
      server: name.replace(/^ProtonVPN[\s:]+/i, "").trim(),
      device: device,
      type: type
    }
  }
  return { active: false, name: "", server: "", device: "", type: "" }
}

// `protonvpn connect` prints "Connected to NL#42 in Amsterdam, Netherlands."
// on success, but not always first: with an expired server list the CLI
// prints "Server list is outdated, updating..." ahead of it. So the line is
// searched for, never assumed to be line 0. Returns "" when there isn't one.
function connectedLine(raw) {
  var lines = stripAnsi(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (/^connected to\s+\S/i.test(line)) return line
  }
  return ""
}

// That line is the only place a Fastest/Random/P2P connect names the server it
// actually landed on, so it's what lets those show up in Recent alongside
// cities picked by hand.
function parseConnected(raw) {
  var line = connectedLine(raw)
  if (line === "") return null
  var m = line.match(/connected to\s+(.+?)\s*\.?\s*$/i)
  if (!m) return null
  var rest = m[1]
  var name = serverName(rest)
  if (name === "") return null
  var location = serverLocation(rest)
  var city = location
  var country = ""
  var comma = location.lastIndexOf(",")
  if (comma > 0) {
    city = location.substring(0, comma).trim()
    country = location.substring(comma + 1).trim()
  }
  return { name: name, city: city, country: country }
}

function filterCountries(countries, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return countries
  var out = []
  for (var i = 0; i < countries.length; i++) {
    var c = countries[i]
    if (c.name.toLowerCase().indexOf(q) !== -1 || c.code.toLowerCase().indexOf(q) === 0) out.push(c)
  }
  return out
}

function elide(text, max) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  var limit = max || 140
  return value.length > limit ? value.substring(0, limit - 3) + "…" : value
}

// `protonvpn config list` -> two-column table:
//
//   Setting                  Value
//   -----------------------  ------------
//   kill-switch              off
//
// Rows are "name<2+ spaces>value"; header and rule are skipped by shape.
function parseConfig(raw) {
  var lines = stripAnsi(raw).split("\n")
  var out = {}
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([a-z][a-z0-9-]*)\s{2,}(\S+)\s*$/i)
    if (!m) continue
    var key = m[1].toLowerCase()
    if (key === "setting") continue
    out[key] = m[2].toLowerCase()
  }
  return out
}

// Proton usernames are an email or a bare account name. Anything outside this
// set is refused outright rather than escaped, it has no business in a
// username, and refusing is simpler to reason about than quoting.
function validUsername(text) {
  return /^[A-Za-z0-9._+@-]{1,254}$/.test(String(text || "").trim())
}

// Single-quote for POSIX sh. The terminal launcher joins its arguments into
// one `bash -c` string, so this is the only path where a value has to cross
// a shell boundary; validUsername() already narrowed it to a safe alphabet.
function shellQuote(text) {
  return "'" + String(text).replace(/'/g, "'\\''") + "'"
}

// The CLI's wording when a feature needs a paid plan.
function isPlanError(text) {
  return /upgrade|plus plan|paid plan|subscription|not available (?:on|for|with) (?:your|the free|free)|free (?:plan|tier|users?)/i.test(String(text || ""))
}
