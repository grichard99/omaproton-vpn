<img src="preview.png" width="720" alt="OmaProton VPN, a live world map, one click to connect, built for Omarchy">

# OmaProton VPN

**Proton VPN, built for Omarchy.** All of Proton in one bar widget for
[Omarchy Quattro](https://omarchy.org): a live world map of every city, one
click to connect, sign-in and the Kill Switch in the panel, none of it in a
terminal. Click the Proton mark and you're protected.

<img src="docs/omaproton.gif" width="360" alt="Live: the map lit on the connected city, traffic moving, and the panel switching through Catppuccin Latte, Gruvbox, Hackerman and Tokyo Night">

*Live, and in your theme.*

## Contents

- [Why "Oma"](#why-oma)
- [New to Proton?](#new-to-proton)
- [What you need](#what-you-need)
- [Install](#install), [Update](#update), [Remove](#remove)
- [How to use it](#how-to-use-it): the bar icon, the map, quick connect,
  countries and cities, traffic, [keyboard](#keyboard)
- [How the protections work](#how-the-protections-work): Kill Switch,
  NetShield, Always On, [port forwarding](#port-forwarding), split tunneling,
  and [why the Kill Switch and split tunneling can't both be on](#why-the-kill-switch-and-split-tunneling-cant-both-be-on)
- [Using it with Tailscale](#using-it-with-tailscale)
- [Settings](#settings)
- [Security and privacy](#security-and-privacy)
- [Notes](#notes), [Credits](#credits), [License](#license)

## Why "Oma"

Because it doesn't look like a VPN app that landed on your desktop. It looks
like Omarchy, because it *is* Omarchy, all the way down:

- **It wears your theme.** Every colour, the font, the corner radius, the
  switches, even the Proton mark and the world map are drawn from Omarchy's
  theme tokens. Switch from Tokyo Night to Catppuccin Latte and the whole
  panel, coastlines, city dots, the lit city, follows on the spot. Nothing is
  a pasted-in bitmap; nothing is hard-coded.
- **It feels like the panels next to it.** The hero, the power switch, the
  rows, the hover rings, the keyboard cursor, all the same Quattro components
  your Wi-Fi, Bluetooth, and Tailscale panels are built from. Arrow keys walk
  it, `Esc` backs out, `/` finds a country. You already know how to use it.
- **It stays out of the terminal.** Install, sign in, Kill Switch, connect,
  pick a city on a map: every step is a click in the panel. The only terminals
  you'll see are Omarchy's own floating ones, the package install's password
  prompt, and Proton's sign-in prompt, and both close themselves.
- **A map, without a map service.** Every Proton city on a world outline, the
  connected one lit and pulsing, hover for load, click to go, all from files
  already on disk. No tiles, no geocoding, no requests.
- **Fast enough to live in a bar.** Tunnel state comes from NetworkManager in
  about ten milliseconds, so the icon reacts in seconds; the Python CLI is only
  asked for the detail rows.

It drives the official `protonvpn` CLI. No API keys, no tokens, and no
credentials are stored by this plugin, your password and 2FA code go straight
into the CLI's own prompt, and Proton's client owns the session from there.

<img src="docs/panel.png" width="360" alt="The OmaProton VPN panel: world map, connection details, live traffic, quick connect">

## New to Proton?

You don't need to be a Proton customer to use this. Proton VPN has a **free
plan**: no data cap, no logs, no ads, run by Proton in Switzerland under Swiss
privacy law. It gets you a handful of countries and standard speeds, which is
plenty to be private on café Wi-Fi. Plus adds every country and city on the
map, faster servers, and the P2P, Secure Core and Tor rows.

Make a free account at [proton.me/vpn](https://proton.me/vpn), then come back
and click the Proton mark. Sign-in happens in the panel.

## What you need

- Omarchy Quattro
- A Proton account, a free one works; sign up at [proton.me](https://proton.me)

That's it. The panel installs the Proton VPN CLI for you if it isn't there.

## Install

```bash
omarchy plugin add https://github.com/grichard99/omaproton-vpn --enable
```

Then click the Proton mark in your bar. The panel walks you through the rest:

1. **Install Proton VPN CLI**: one click; Omarchy opens a terminal and handles
   the install (that terminal asks for your password, since it's a system
   package).
2. **Sign in**: type your Proton username or email in the panel and press
   Enter. A terminal opens for your password and 2FA code, then closes.
3. **Turn on the Kill Switch**: the panel offers this once. Say yes.
4. **Connect**: the switch at the top, or pick a city below.

If you'd rather place the widget yourself, drop `--enable` and run:

```bash
omarchy plugin enable io.github.grichard99.omaproton-vpn right
```

### Already have the Proton VPN desktop app?

The desktop app and the CLI can't run at the same time. The panel warns you if
the app is installed. Quit it before connecting, or remove it from the Omarchy
menu under Remove → Package (`proton-vpn-gtk-app`).

### Two-factor with a security key?

The CLI supports TOTP (authenticator-app codes) only. If your account uses a
FIDO2 key, sign in once with the desktop app instead, this widget reads the
session either way.

## Update

```bash
omarchy plugin update io.github.grichard99.omaproton-vpn
```

## Remove

```bash
omarchy plugin remove io.github.grichard99.omaproton-vpn
```

That disables the widget, removes it from your bar, and deletes the plugin
folder. It leaves your Proton VPN session, settings, and any active tunnel
alone, disconnect and sign out first if you want those gone too:

```bash
protonvpn disconnect
protonvpn signout
```

The widget also keeps a small folder of its own at
`~/.local/state/omarchy-protonvpn/` (your recent locations and the icon it
uses in notifications); delete it if you like.

## How to use it

### The bar icon

The Proton mark sits in your bar in the theme's foreground colour. Solid means
protected; dimmed means not.

| Action | What it does |
| --- | --- |
| Left-click | Open the panel |
| Right-click | Toggle: connect to the fastest server, or disconnect |
| Middle-click | Force a status refresh |

The panel is fully keyboard-driven too; see [Keyboard](#keyboard).

### The map

<img src="docs/map.png" width="360" alt="World map with every Proton city as a dot and the connected city lit">

Under the header is a world map. Every dot is a city Proton has servers in;
the bright, pulsing one is where your traffic exits right now. Hover a dot for
the city and its current load; click it to open that country's city list.

It's drawn entirely offline. The coastlines are a single bundled outline
(Natural Earth, public domain), the dots come from the Proton client's own
server cache, and the connected city is looked up in that same cache by server
name. No map tiles, no geocoding, no requests.

The map doesn't show *your* location or draw a line to the server, the way the
Proton app does. Finding your location would take a geo-IP lookup, which this
plugin promises never to make. Lighting up the exit city is the honest version.

On a Secure Core connection the map does draw the route: a dashed arc from the
entry country (Switzerland, Iceland or Sweden, ringed) to the city you exit
from, just like the Proton app. Both ends are Proton servers named in the
server cache, so no lookup about you is involved.

### The power switch

The switch at the top of the panel is the same toggle as right-click. When off,
it connects to the **fastest server for your location**: Proton's own choice,
the same thing `protonvpn connect` with no arguments does. When on, it
disconnects.

### Quick connect

Each row asks Proton for the **fastest server that has that feature**. You don't
pick a country here; Proton picks the best match for you.

| Row | What you get |
| --- | --- |
| **Fastest** | Proton's best pick for your location. Same as the power switch. |
| **Random** | Any available server, chosen at random. Useful when you want to look like you're somewhere unpredictable. |
| **P2P** | The fastest server that permits file sharing. Only P2P-flagged servers allow BitTorrent-style traffic; on other servers it's blocked. |
| **Secure Core** | The fastest Secure Core server. Your traffic enters through a hardened server in Switzerland, Iceland, or Sweden and *then* exits through the country you appear from, so a compromised exit server never sees your real IP. Slower, because it's two hops. |
| **Tor** | The fastest Tor-over-VPN server. Your traffic goes VPN first, then into the Tor network, so you can reach `.onion` sites from a normal browser. Noticeably slower. |

Rows marked **PLUS** need a paid plan. On a free plan they fail with a clear
"Requires a Proton VPN Plus plan", nothing breaks.

After a **P2P** connect the header reads "󰒗 P2P · US-TX#40" and the Server
row "US-TX#40 · P2P", so you can see the click landed. Most Proton servers permit P2P, so the panel only makes a
point of it when that's what you asked for.

While you're on Secure Core the panel says so three ways: the header reads
"󰦝 Secure Core · CH → US#3" (the entry country, then the exit server), the
Server row reads "CH → US#3 · Secure Core", the Secure Core row carries an
**ACTIVE** tag, and the map draws the route from the entry country to the city
you exit from.

### Two tabs: Connections and Protection

Under Quick Connect sit two tabs, in the same pill style as Omarchy's network
panel. **Connections** holds everywhere you can go: recent places, and the
country and city lists. **Protection** holds everything about *how* you're
protected: the Kill Switch, NetShield, Always On, port forwarding, split
tunneling, and your
account. The tab you pick stays until you close the panel.

The Protection tab has enough rules behind it to deserve its own chapter:
[How the protections work](#how-the-protections-work).

### Connections → Recent

The last three places you connected to, pinned above the country list. Most
people use the same two or three locations forever; this makes them one click.

Every successful connection lands here, including **Fastest**, **Random**,
**P2P**, **Secure Core** and **Tor**. Those don't name a destination when you
click them, but they still put you somewhere, so the server they picked is
recorded by name and city, and clicking it again takes you straight back.
That top entry is also what Always On reconnects to.

### Connections → Countries and cities

Below that is the full country list. **Clicking a country doesn't connect**,
it drills into that country's cities, so you can see where you'll land before
you commit.

<img src="docs/city-list.png" width="360" alt="Connections tab with Japan drilled open, Osaka, clicked on the map, is ringed">

Inside a country:

- **"Fastest in &lt;country&gt;"** is always the first row. It lets Proton choose
  any server in that country, which is the same as `protonvpn connect --country`.
- **Every row below is one city**, showing the best server there right now with
  its current load and any tags: **Free** for free-plan servers, plus P2P, Tor,
  or Streaming. Cities are ordered by Proton's own speed score, best first.

The widget shows one row per city rather than one per server on purpose. Large
countries have thousands of servers and the nearest city would monopolise the
whole list; you'd scroll past hundreds of near-identical entries before seeing
a second city. When you pick a city, it connects to that city's best server; if
you want a *specific* server, use the CLI: `protonvpn connect US-NY#12`.

Secure Core servers aren't listed under their exit country. They're reached
through the Secure Core quick-connect row instead, since listing them here would
suggest a single-hop connection that isn't.

The city list comes from the Proton client's own cache, which is written the
first time you connect. Before that, every country shows only the "Fastest in"
row.

### The detail rows

When connected, the panel shows the server, its location, load, and protocol,
exactly what `protonvpn status` prints.

The **Server** line updates within seconds from NetworkManager even while a
connect is still in progress. The other rows come from the CLI and can lag a
moment behind.

With [port forwarding](#port-forwarding) on and a P2P server connected, a
**Forwarded port** row appears. Click it to copy the number; it reads "Copied"
for a moment. Paste it into your torrent client's listening port.

### Traffic

<img src="docs/traffic.png" width="360" alt="Download and upload rates with the 60-second sparkline and session totals">

While you're connected, under the details: download and upload rates, a
60-second sparkline, and the session's totals and uptime. Download is the
filled area with a solid line; upload is the dashed line. Both are drawn in
your theme's foreground, one ink, like the rest of the panel, and told apart
by shape, not colour, so they read the same on every theme and for
colour-blind eyes. Hover the sparkline to read the values at any second.

The numbers come from the kernel's own counters for the tunnel interface
(`/sys/class/net/proton0/statistics`), read once a second **only while the
panel is open**: so it's tunnel traffic specifically, and it costs nothing
when you're not looking.

### While a connect is in progress

`protonvpn connect` blocks for anywhere from a few seconds to a minute. The
widget doesn't freeze: it shows "Connecting to …" and optimistically flips the
switch on. If the connect fails, the switch drops back and the reason is shown
under the header for a few seconds.

### Keyboard

Everything in the panel is reachable without a mouse.

| Key | What it does |
| --- | --- |
| `↑` `↓` or `k` `j` | Move through every section, top to bottom |
| `→` or `l` | Open the selected country's city list |
| `←` or `h` | Back out to the country list |
| `Enter` | Activate: connect, flip a switch, open a picker |
| `Esc` | Back out one level, then close the panel |
| `/` | Jump to the country filter |

There are no single-letter shortcuts on purpose: the panel takes keyboard
focus when it opens, and a stray keystroke should never change your
connection.

`Enter` on **Mode** or **Apps** opens that picker, which then owns the
keyboard: inside the Apps list, typing filters it, arrows move, `Enter` ticks,
and `Esc` closes it again. The Kill Switch and Port forwarding dialogs work
the same way: arrows move between Cancel and confirm, `Enter` chooses, `Esc`
cancels.

Hover only moves the selection when you actually move the pointer. Scrolling
with the keyboard slides rows under a stationary mouse, and without that rule
the row that lands under the pointer would drag the selection back to itself.

## How the protections work

<img src="docs/protection-tab.png" width="360" alt="The Protection tab: Kill Switch, NetShield, Always On, Port forwarding and split tunneling switches, account, and sign out">

Five switches, three owners. Knowing who owns each one explains most of how
they behave:

| Switch | Saved by | Where | Needs |
| --- | --- | --- | --- |
| **Kill Switch** | Proton CLI (`protonvpn config set`) | Proton's settings | Tunnel down to change |
| **NetShield** | Proton CLI (`protonvpn config set`) | Proton's settings | Plus plan for ads and trackers |
| **Port forwarding** | Proton CLI (`protonvpn config set`) | Proton's settings | Plus plan, and a P2P server for a port |
| **Always On** | This widget | `~/.local/state/omarchy-protonvpn/state.json` | Nothing |
| **Split tunneling** | This widget, editing Proton's file | `~/.config/Proton/VPN/settings.json` | Kill Switch off |

### Kill Switch

If the VPN drops, your internet is blocked until it's back. Without it, a
dropped tunnel silently falls back to your plain connection and all you'd see
is the icon dimming. The CLI ships with it **off**, which is why the panel
offers to turn it on the first time you sign in. Say yes; it's the setting
that makes the others matter.

Proton implements it in NetworkManager, below any app, so it holds even if the
Proton client itself crashes. It also keeps an IPv6 leak guard active
independently of the tunnel.

### NetShield

Blocks malware, ads, and trackers at the DNS level, on Proton's side. Three
levels: off, malware only, or malware plus ads and trackers. The switch asks
for the full level; on a free plan Proton only allows malware blocking, and
the widget steps down to that automatically instead of failing.

### Always On

Whenever Proton isn't connected, connect it. That covers booting, logging in,
joining a café Wi-Fi, and a tunnel that drops on its own: they're all just
moments when you aren't protected and should be. It's checked on the same
few-second poll that drives the bar icon, so there's nothing extra running.
**Off by default.**

It reconnects to the top of your **Recent** list, which is the server you were
last actually on. If that server is full or gone, the attempt fails once and
the next one falls back to Fastest, so it can't get stuck retrying a server
that isn't coming back. With nothing in Recent yet it just uses Fastest. A
connect that fails waits 30 seconds before trying again, so a dead network, or
a café portal you haven't signed into yet, doesn't get hammered.

Two things worth knowing:

- It never fires while you're signed out, and it will never open a sign-in
  terminal on its own.
- While it's on, **Disconnect** won't keep you disconnected; you'll be
  reconnected within a few seconds. Switch Always On off if you want to stay
  off.

Always On and the Kill Switch are different answers to the same question.
The Kill Switch stops traffic leaking *while* the tunnel is down; Always On
makes the tunnel come *back*. Together they close the gap from both sides:
nothing leaks, and you're not stuck offline.

### Port forwarding

For torrent clients. When on, connecting to a **P2P server** (Quick connect →
P2P, or any city whose servers carry the P2P flag) asks Proton for an inbound
port, and the panel shows it as a **Forwarded port** row you click to copy. On
any other server there is no port and the switch says so. Turning it on asks
first, like the Kill Switch does, because it opens an inbound port on your VPN
address and sends whatever arrives there to this computer. Turning it off is
immediate.

Proton hands the port out over NAT-PMP from the tunnel gateway and drops it
unless it's renewed, which is why Proton's guide has you run a `natpmpc` loop
in a terminal. The switch is that loop: while it's on and the tunnel is up,
the widget renews the mapping every 45 seconds with a small script of its own
(`port.py`, standard library only, no `natpmpc` to install). Turn it off and
the renewals stop. Off by default: a forwarded port is an open inbound door,
and nobody gets one without asking. Paid plans only, like the other Proton
features.

### Split tunneling

Turn it on and two more rows appear: **Mode**, and the **Apps** list.

- **Exclude** (the default) sends the apps you pick out through your normal
  connection; everything else stays on the VPN. Good for a bank that blocks
  VPN IPs, or a device on your own network.
- **Include** is the mirror image: only the apps you pick go through the VPN,
  and everything else uses your normal connection.

The Apps list is every desktop app on the machine that the widget can point at
a real program on disk. Search it, tick what you want, untick to remove. Each
mode remembers its own list, so switching modes doesn't lose either one.

How Proton does it, so the caveats make sense: while split tunneling is
active, Proton's system service watches every program you start and tags the
connections of the ones you picked (and anything they launch) so the kernel
routes them around the tunnel, or through it in Include mode. Which is why:

- **Restart your apps after connecting.** Connections are tagged as they're
  made, so anything already running when the tunnel came up keeps using it
  until you restart it. Proton's own app tells you the same thing.
- **Apps only, no IP ranges.** Proton's settings file has a field for IP ranges
  but nothing on Linux reads it yet, so the widget doesn't offer one rather
  than write a setting that does nothing.
- **IPv4 only.** Proton tags IPv4 connections and nothing else, so an app you
  excluded still uses the VPN for anything it sends over IPv6, and in Include
  mode an app you left out still uses the VPN over IPv6. If you need an
  exclusion to be absolute, `protonvpn config set ipv6 off` stops the tunnel
  carrying IPv6 at all and apps fall back to IPv4, where it works. When you
  test this, check with `curl -4`, otherwise you may be looking at a path
  split tunneling never touches.
- **Flatpaks and Snaps aren't listed.** They all launch through one shared
  runner, so picking one would pick all of them. Same for anything that
  launches through a terminal chooser or a web-app handler.

### Why the Kill Switch and split tunneling can't both be on

Because Proton ignores split tunneling whenever the Kill Switch is on. That's
not a limitation the widget could hide; it's the rule Proton's own service
follows, and it makes sense once you see the two as a trade:

- The **Kill Switch** promises that if the tunnel drops, *nothing* leaks.
- **Split tunneling** deliberately punches holes in the tunnel for the apps you
  chose.

A tunnel with holes in it can't also promise nothing leaks, so Proton picks
the stricter one and skips the other. What the widget does with that:

- Each row **locks the other** and says which one to turn off. With the Kill
  Switch on, the Split tunneling row reads "Turn the Kill Switch off to use
  this". With split tunneling on, the Kill Switch row reads "Turn split
  tunneling off to use this". You never have to know the rule to get past it.
- The switches **tell the truth**. If the Kill Switch is on, the Split
  tunneling switch shows *off*, because nothing is being split, whatever the
  setting says underneath. It stays off when you turn the Kill Switch back
  off, and your app lists are kept, so bringing it back is one click. Neither
  switch ever turns itself on.
- So the order, if you want split tunneling, is: **Kill Switch off, then split
  tunneling on**. And when you're done: **split tunneling off, then Kill
  Switch back on**. The panel walks you through both.

### Changing the Kill Switch while connected

<img src="docs/kill-switch-confirm.png" width="360" alt="The confirmation dialog: turning the Kill Switch off needs the tunnel down, with Cancel preselected">

Proton refuses to change the Kill Switch while a tunnel is up, so a switch you
could only use while disconnected wouldn't be much of a switch. If you flip it
while connected, the widget does the whole thing for you: drops the tunnel,
makes the change, and puts you back on the same server.

That gap is the one moment your traffic isn't protected, so the widget **asks
first**, in a dialog, with Cancel preselected; an accidental `Enter` does
nothing. Disconnected, there's nothing to interrupt, so the change just
happens. The row says "Turning on…" or "Turning off…" the whole way through,
and Always On is held off in the middle, otherwise it would reconnect into the
gap and the change would fail. If anything goes wrong, you end up back on the
VPN with the setting unchanged, never stranded off it.

### Which setup do I want?

| You want | Kill Switch | Split tunneling | Always On |
| --- | --- | --- | --- |
| Everything private, always. The default recommendation. | On | Off | On |
| Everything private, except one app that refuses to work over a VPN | Off | Exclude that app | On |
| Only one app private (a torrent client, a browser for one site) | Off | Include that app | Your call |
| Nothing automatic; I connect by hand | Off | Off | Off |

Torrenting with a reachable port is any of these rows plus
[port forwarding](#port-forwarding) on and a P2P server.

Note the second and third rows have the Kill Switch off, because they have to.
If that one app is a bank that blocks VPN IPs, consider whether a second
browser profile without the VPN is a better fit than a hole in the tunnel.

### Account and sign out

Below the switches, **Account** shows who's signed in and the plan, with a
**Sign out** row. It asks for a second click within five seconds, because
signing out also disconnects.

### Notifications

If the VPN drops unexpectedly you get a desktop notification, "VPN
Disconnected, You're no longer protected." Connecting shows "VPN Connected"
with the server and the protocol. Neither shows while the panel is open, since
the panel already tells you. Turn both off in the widget's settings if you'd
rather not.

## Using it with Tailscale

They work great together. Tailscale only carries traffic between your own devices;
Proton carries everything else. Out of the box the two split the work instead
of fighting over it, so your tailnet stays reachable while the VPN is up, and
nothing here needs configuring. The three situations below are the ones people
actually hit.

### If Tailscale machines aren't reachable, check the Kill Switch first

The Kill Switch blocks any traffic that doesn't go through Proton's tunnel,
and Tailscale's direct device-to-device connections are exactly that kind of
traffic. If your peers drop off the moment you connect, this is almost always
why. There's no setting that makes the two promises compatible, a Kill Switch
with a Tailscale-shaped hole in it wouldn't be a Kill Switch, so it's a
choice: Kill Switch on and Proton owns everything, or Kill Switch off and
Tailscale runs alongside.

### If devices answer by IP but not by name

Proton points your DNS at its own resolver inside the tunnel. Tailscale's
MagicDNS names (`something.ts.net`) usually keep resolving alongside it, but
if they stop while `tailscale status` still lists your devices and their
`100.x` addresses still answer, nothing is down, only name lookup. Reach the
device by its `100.x` address, or disconnect Proton for a moment to confirm
that's all it is.

### Tailscale Exit nodes

A Tailscale exit node routes **all** of a device's internet traffic through
another machine on your tailnet, which makes it a second full VPN, and two
full VPNs on one machine both want to own where your packets go.

| You want | Do this |
| --- | --- |
| Proton here, tailnet devices reachable | Just connect. The everyday case; nothing to set up. |
| Your traffic to exit through Proton on a machine at home | Run Proton on the home machine and use it as your exit node; this laptop runs Tailscale only. Traffic goes laptop, tailnet, home machine, out through its Proton tunnel, and shows Proton's IP to the world. |
| Proton on this machine *while* using an exit node | Don't. Both claim your default route, and Proton's in-tunnel DNS can stop resolving anything at all. Pick one at a time. |

For the middle row, two settings on the home machine make it dependable: keep
its Kill Switch **off** (it would block the tailnet link your traffic arrives
on) and turn **Always On** on, so the Proton tunnel your remote traffic
depends on comes back by itself. One honest caveat: if that tunnel is down,
your traffic still flows, just from the home connection's own IP rather than
Proton's.

## Settings

Configurable from Omarchy's widget settings:

| Setting | Default | What it controls |
| --- | --- | --- |
| Desktop notifications | On | "VPN Connected" with the server and protocol on connect; "VPN Disconnected" if the tunnel drops unexpectedly. Not shown while the panel is open, since the panel already says so. |
| Status refresh interval | 30 s | How often `protonvpn status` runs for the detail rows while the panel is closed. Open panel: every 5 s. |
| Link watch interval | 4 s | How often `nmcli` is polled for the bar icon. |

**Protocol.** The one Proton setting the CLI doesn't expose. It lives in
`~/.config/Proton/VPN/settings.json`:

```json
{ "protocol": "wireguard" }
```

Valid values are `wireguard`, `openvpn-udp`, and `openvpn-tcp`. Reconnect after
changing it. `wireguard` is the fastest and the CLI warns about instability on
`openvpn-tcp`.

## Security and privacy

This plugin runs unsandboxed inside the Omarchy shell process, like every
Omarchy plugin. It:

- stores no credentials, tokens, or account data
- makes no network requests of its own, with one exception you switch on:
  with port forwarding on and the tunnel up, `port.py` sends a NAT-PMP renewal
  to the VPN gateway (`10.2.0.1`, inside the tunnel) every 45 seconds. That is
  the same exchange Proton's own guide has you run, it goes nowhere else, and
  the answer is only shown in the panel and copied to the clipboard when you
  click it
- never asks for root, the CLI install runs through Omarchy's own installer
  in a terminal that owns the password prompt
- never downloads or executes remote code
- runs every command as an argument list, never through a shell, with one
  exception below
- reads Proton's server cache read-only (city list, coordinates, and the map's
  connected-city lookup all come from it), reads the tunnel's byte counters
  under `/sys/class/net/` once a second while the panel is open, and writes
  two files of its own under `~/.local/state/omarchy-protonvpn/`
  (`state.json`: recent location labels, whether you dismissed the Kill
  Switch prompt, and whether Always On is on; `notification-icon.svg`: the
  Proton mark in your theme's colour, for the notification)
- writes one file that isn't its own, and only if you turn split tunneling on:
  `~/.config/Proton/VPN/settings.json`, Proton's own settings. Rules below.

**Sign-in.** Your password and 2FA code go straight to the `protonvpn` CLI's
own prompt in a terminal; this plugin never sees them. The username you type in
the panel is the one value that has to cross a shell boundary (Omarchy's
terminal launcher takes a command string). It's checked against a strict
allow-list, letters, digits, and `. _ + @ -` only, and single-quoted before
it goes anywhere; anything else is refused with a message, not escaped. The
terminal runs non-interactively, so nothing lands in your shell history.

**Settings writes.** The Kill Switch, NetShield and port forwarding switches run
`protonvpn config set`. The widget will only ever pass `kill-switch` ∈
`{off, standard}`, `netshield` ∈ `{off, malware-only, malware-ads-trackers}`
and `port-forwarding` ∈ `{off, on}`; no other key or value can reach the CLI
from this code.

**Writing Proton's settings file.** Split tunneling is the one feature with no
CLI command behind it, so the widget edits `~/.config/Proton/VPN/settings.json`
itself. What that means in practice:

- It only ever happens when you change something under Split tunneling.
  Nothing is written on start-up, on a poll, or when you connect.
- The file is read fresh, only `features.split_tunneling` is changed, and every
  other key is handed back exactly as found. A diff before and after a change
  shows the app list and nothing else.
- If the file is missing or unreadable, nothing is written and the row says
  "Sign in and connect once first". The widget never creates it.
- App paths only ever come from the widget's own scan of installed apps, and
  anything that isn't an absolute path is dropped rather than repaired.
- Writes are atomic (written aside, then renamed into place), so an interrupted
  write can't leave you with half a settings file.
- Nothing is written while the Kill Switch is on, since Proton would ignore it,
  and nothing is written while a `protonvpn config set` is still running, so
  the two can't land on the file at once.

**What's visible to other processes.** Omarchy exposes every plugin over a
Quickshell IPC socket under `/run/user/<uid>/`, which only your own user (and
root) can reach. Through it, any process running as you can call this widget's
`connect`, `disconnect`, `status`, and `debug` methods, the same things that
process could already do by running `protonvpn` directly. Note that while
Always On is enabled, an IPC `disconnect` is undone within a few seconds, same
as the button. `status` returns the
server name; `debug` deliberately omits your account email. The email is shown
only inside the panel.

**Network activity.** The widget polls `nmcli` (local, no network) for the bar
icon, and `protonvpn status` for the detail rows. `status` asks the Proton
client for its server list, which the client refreshes from Proton's API only
when its own cache has expired, server loads every ~15 minutes, the full list
every ~3 hours, and only while connected. The widget's polling doesn't add API
traffic beyond what the client already does on its own schedule.

**Notifications** are sent straight to the desktop notification service over
D-Bus and contain only the connection state, the server and its location, and
the protocol.

**On screen.** Your Proton account email is shown only under Protection →
Account, not in the panel's default view, but if you screenshot or
screen-share that tab, it's visible.

## Notes

**How state is detected.** `protonvpn status` costs about a second of Python
start-up, which is far too slow to poll for a bar icon. The tunnel also appears
as an active NetworkManager connection named `ProtonVPN <server>` on device
`proton0`, which `nmcli` reports in around ten milliseconds. The widget polls
`nmcli` for the icon and only shells out to the CLI for the detail rows. Proton's
IPv6 leak guard (`pvpn-killswitch-ipv6`, on a dummy device) stays active
independently and is deliberately not counted as a live tunnel.

**Where the city list comes from.** The CLI has no server-list command
(`protonvpn servers` just prints a URL), but the Proton client caches the full
logical server list at `~/.cache/Proton/VPN/serverlist.json` and refreshes it on
every connect. `servers.py` reads that cache read-only and collapses it to one
row per city.

## Credits

The world outline is [Natural Earth](https://www.naturalearthdata.com/) 1:110m
land data, free, public-domain map data made by volunteers, and the reason this
widget can draw a map without calling anyone. Projected once into `World.js`.
The Proton VPN mark is drawn from the [Simple Icons](https://simpleicons.org)
path (CC0) and recoloured to the active theme, so it isn't a scaled bitmap.
Proton and Proton VPN are trademarks of Proton AG. This is an unofficial
community plugin and is not affiliated with or endorsed by Proton AG.

## License

[MIT](LICENSE)
