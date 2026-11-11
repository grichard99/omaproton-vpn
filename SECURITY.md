# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository:

**https://github.com/grichard99/omaproton-vpn/security/advisories/new**

It goes only to the maintainer. Please include what you found, how to
reproduce it, and what you think the impact is. You'll get a reply, and
credit in the fix if you want it.

Please don't open a public issue for anything that could expose a user's
traffic, credentials, or session.

## What this widget does and doesn't do

Short version, the long one is in the README's *Security and privacy*
section:

- Stores no credentials, tokens, or account data. Sign-in goes to the
  Proton CLI's own prompt in a terminal; the widget never sees the password
  or 2FA code.
- Makes two kinds of network request of its own, both only through the VPN
  tunnel: a NAT-PMP renewal to the VPN gateway while port forwarding is
  switched on, and one request to `https://ip.me` for the Exit IP row when
  the panel is opened while connected. ip.me is owned by Proton and exists
  for exactly this, telling you which address the internet sees you as (the
  domain is registered to Proton AG, see `whois ip.me`). The
  request carries no account or identifier, is bound to the tunnel device,
  so it fails if the VPN is down and never goes out over the normal
  connection, and all ip.me can see is the VPN's exit address. The world map is drawn from bundled data and
  the Proton client's own cache.
- Never asks for root. The CLI install goes through Omarchy's installer, which
  owns the password prompt in a terminal.
- Runs every command as an argument list, never through a shell, except the
  username handed to Omarchy's terminal launcher, which is allow-listed and
  quoted first.
- Writes one file of its own (`~/.local/state/omarchy-protonvpn/state.json`,
  owner-only) and, only when you change split tunneling, one section of
  Proton's own `~/.config/Proton/VPN/settings.json`. Every other key in that
  file is handed back exactly as found; the README lists the full rules.

## Trust boundary

Like every Omarchy plugin, this runs unsandboxed as your user. It is not a
defence against root, against a compromised shell, or against other software
running as you. Its job is to never make that boundary worse.

## Single-author policy

Only the maintainer commits to this repository. Pull requests are closed
rather than merged, as a defence against the AI-generated and supply-chain
pull requests that public projects now attract; findings in them are re-filed
as issues and credited. See [CONTRIBUTING.md](CONTRIBUTING.md).
