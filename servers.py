#!/usr/bin/env python3
"""Extract one country's Proton VPN locations from the client's own cache.

The CLI has no server-list command (`protonvpn servers` just prints a URL), but
the GTK/CLI client caches the full logical server list, ~18k entries, at
~/.cache/Proton/VPN/serverlist.json, refreshed whenever it connects. Reading it
here is far cheaper than a 1s CLI round-trip and gives us load and tier per
server, which `protonvpn connect <NAME>` then accepts directly.

Results are collapsed to ONE ROW PER CITY, keeping that city's best server.
A flat score-sorted list is useless in practice: large countries carry
thousands of servers and whichever city is nearest monopolises the entire top
of the list, so you'd scroll past hundreds of near-identical entries before
seeing a second city. One row per city is the choice a person actually wants
to make.

Usage: servers.py <COUNTRY_CODE> [limit]   one country's cities, best-first
       servers.py --cities                  every city worldwide, with lat/long,
                                            and the account's tier
       servers.py --locate <SERVER_NAME>    one server's city and coordinates
Prints compact JSON, or [] / {} when the cache is missing.
"""
import ipaddress
import json
import math
import os
import sys

# Proton's feature bitmask, from proton.vpn.session.servers.enums.
SECURE_CORE = 1
TOR = 2
P2P = 4
STREAMING = 8

CACHE = os.path.expanduser("~/.cache/Proton/VPN/serverlist.json")
# The client's record of the live connection: which physical machine of a
# logical server it picked, by that machine's IP.
CONNECTION = os.path.expanduser("~/.cache/Proton/VPN/connection/connection_persistence.json")

# The real list is about 25 MB and the connection record under 1 KB.
CACHE_LIMIT = 256 * 1024 * 1024
CONNECTION_LIMIT = 1024 * 1024


def labels(features):
    out = []
    if features & P2P:
        out.append("P2P")
    if features & TOR:
        out.append("Tor")
    if features & STREAMING:
        out.append("Streaming")
    return out


def read_json(path, limit):
    """What a regular file of sane size holds, or None.

    Anything else is refused before it is opened: a pipe would block for
    ever and a device never ends.
    """
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > limit:
            return None
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return json.load(fh)
    except (OSError, ValueError, RecursionError, MemoryError):
        return None


# Every value below is read from a file this script doesn't own. Each field
# is taken only in the type and range it is meant to have, so one odd record
# costs that record and nothing else.

def text(value, limit):
    """A single-line printable string no longer than limit, or ""."""
    if not isinstance(value, str):
        return ""
    value = "".join(ch for ch in value if ch.isprintable())
    return " ".join(value.split())[:limit]


def whole(value):
    """An int of ordinary size, or None. A bool is an int in Python and
    must not pass as one."""
    if type(value) is int and -2 ** 31 < value < 2 ** 31:
        return value
    return None


def number(value, low=None, high=None):
    """A finite number, within [low, high] when given, or None."""
    if type(value) not in (int, float):
        return None
    try:
        if not math.isfinite(value) or abs(value) > 1e300:
            return None
    except OverflowError:
        return None
    if low is not None and not low <= value <= high:
        return None
    return value


def coords(s):
    """A server's exit coordinates as (lat, lon), or (None, None).

    Newer server lists carry them in ExitLocation as Latitude/Longitude (with
    an EntryLocation beside it); older ones in Location as Lat/Long. Read the
    new shape first so both keep working.
    """
    for field, lat_key, lon_key in (("ExitLocation", "Latitude", "Longitude"),
                                    ("Location", "Lat", "Long")):
        loc = s.get(field)
        if not isinstance(loc, dict):
            continue
        lat = number(loc.get(lat_key), -90, 90)
        lon = number(loc.get(lon_key), -180, 180)
        if lat is not None and lon is not None:
            return lat, lon
    return None, None


def clean(s):
    """One logical server with every field in its expected type, or None."""
    if not isinstance(s, dict):
        return None
    lat, lon = coords(s)
    machines = s.get("Servers")
    return {
        "name": text(s.get("Name"), 64),
        "city": text(s.get("City"), 80),
        "exit": text(s.get("ExitCountry"), 8).upper(),
        "entry": text(s.get("EntryCountry"), 8).upper(),
        "features": whole(s.get("Features")) or 0,
        "status": whole(s.get("Status")),
        "score": number(s.get("Score")),
        "load": whole(s.get("Load")),
        "tier": whole(s.get("Tier")),
        "lat": lat,
        "lon": lon,
        "machines": [m for m in machines if isinstance(m, dict)] if isinstance(machines, list) else [],
    }


def read_servers():
    """(servers, max_tier) from the client's cache, or (None, None)."""
    data = read_json(CACHE, CACHE_LIMIT)
    if not isinstance(data, dict):
        return None, None
    raw = data.get("LogicalServers")
    servers = [c for c in map(clean, raw if isinstance(raw, list) else []) if c]
    tier = whole(data.get("MaxTier"))
    return servers, tier if tier is not None and 0 <= tier <= 16 else None


def status_known(servers):
    """Whether Status carries any information in this cache.

    Proton fills Status in from a *separate* "loads" refresh
    (`Status = 1 if server_load.enabled else 0` in its own types.py). Until
    that call has succeeded, or when it fails, every server in the file reads
    Status 0. That means "we don't know yet", not "all 18,000 servers are
    down", and taking it literally empties the map and every city list.

    So Status is honoured only when at least one server is marked up.
    """
    return any(s["status"] == 1 for s in servers)


def usable(s, check_status=True):
    """Connectable, and not Secure Core (those are reached via --securecore)."""
    if check_status and s["status"] != 1:
        return False
    return not (s["features"] & SECURE_CORE)


def all_cities(servers):
    """Every city worldwide: one entry per (country, city) with its coordinates
    and best server. Feeds the panel's mini-map; ~200 rows for ~18k servers."""
    out = {}
    check_status = status_known(servers)
    for s in servers:
        if not usable(s, check_status):
            continue
        if s["lat"] is None:
            continue
        code, city = s["exit"], s["city"]
        if code == "" or city == "":
            continue
        score = s["score"] if s["score"] is not None else 9e9
        key = (code, city)
        entry = out.get(key)
        if entry is None or score < entry["score"]:
            out[key] = {
                "code": code,
                "city": city,
                "lat": round(float(s["lat"]), 3),
                "lon": round(float(s["lon"]), 3),
                "name": s["name"],
                "load": s["load"],
                "tier": s["tier"],
                "score": score,
                "count": (entry["count"] + 1) if entry else 1,
            }
        else:
            entry["count"] += 1
    rows = sorted(out.values(), key=lambda r: (r["code"], r["city"]))
    for r in rows:
        del r["score"]
    return rows


def country_place(servers, code):
    """Where a country is, for the map: the location of its first regular
    server. Secure Core entry countries (CH, IS, SE) each have one city."""
    for s in servers:
        if s["exit"] != code or s["features"] & SECURE_CORE or s["lat"] is None:
            continue
        return {"code": code, "city": s["city"], "lat": s["lat"], "lon": s["lon"]}
    return None


def clean_ip(value):
    """value as a dotted IPv4 address, or None. IPv6 is left out on purpose:
    its zone suffix admits arbitrary text."""
    if not isinstance(value, str):
        return None
    try:
        return str(ipaddress.IPv4Address(value.strip()))
    except ValueError:
        return None


def server_ip(s):
    """The address the client connects to for this server, or None.

    This is the server's inbound address. The address websites see (the exit
    IP) is a different one on many servers and isn't in the list at all: its
    ExitIP field repeats the inbound address. The panel looks that one up
    separately.

    On a regular server every physical machine behind one name shares one
    address, so the name alone is enough. Secure Core names have several
    entry machines, so the one in use is picked out by the client's own
    connection record. If that record names another server (written late, or
    left from an earlier connection), return nothing rather than a guess.
    """
    known = {clean_ip(m.get("EntryIP")) for m in s["machines"]} - {None}
    if not s["features"] & SECURE_CORE:
        return known.pop() if len(known) == 1 else None
    record = read_json(CONNECTION, CONNECTION_LIMIT)
    record = record.get("server") if isinstance(record, dict) else None
    if not isinstance(record, dict):
        return None
    if text(record.get("server_name"), 64).upper() != s["name"].upper():
        return None
    ip = clean_ip(record.get("server_ip"))
    return ip if ip in known else None


def locate(servers, name):
    """Where one server is. Used to light up the connected city on the map.
    A Secure Core server (CH-US#3: enters Switzerland, exits New York) also
    carries its entry hop so the map can draw the route."""
    want = name.strip().upper()
    for s in servers:
        if s["name"] == "" or s["name"].upper() != want:
            continue
        place = {
            "name": s["name"],
            "code": s["exit"],
            "city": s["city"],
            "lat": s["lat"],
            "lon": s["lon"],
            # Feature bit 4 is P2P. Most servers permit it, so the panel only
            # makes a point of it when that's what you asked for.
            "p2p": bool(s["features"] & P2P),
        }
        ip = server_ip(s)
        if ip:
            place["ip"] = ip
        if s["features"] & SECURE_CORE and s["entry"] and s["entry"] != place["code"]:
            entry = country_place(servers, s["entry"])
            if entry:
                place["entry"] = entry
        return place
    return {}


def country_cities(servers, code, limit):
    """One country's cities, best server first."""
    # city -> best server seen so far, plus a count of that city's servers.
    cities = {}
    check_status = status_known(servers)
    for s in servers:
        # Status 0 means under maintenance, but only once we know Status has
        # been populated at all: see status_known().
        if check_status and s["status"] != 1:
            continue
        if s["exit"] != code:
            continue
        # Secure Core entries are reached via --securecore, not by name here;
        # listing them under their exit country would be misleading.
        if s["features"] & SECURE_CORE:
            continue

        # Some servers carry no city; group them together rather than dropping
        # them, so small countries don't come back empty.
        city = s["city"] or "Other"
        score = s["score"] if s["score"] is not None else 9e9
        load = s["load"] if s["load"] is not None else 999
        best = {
            "name": s["name"],
            "load": s["load"],
            "tier": s["tier"],
            "score": score,
            "tags": labels(s["features"]),
        }

        entry = cities.get(city)
        if entry is None:
            cities[city] = dict(best, city=city, count=1)
            continue

        entry["count"] += 1
        # Score is Proton's own "fastest" metric (lower is better) and is what
        # the CLI sorts on; load breaks ties.
        if (score, load) < (entry["score"], entry["load"] if entry["load"] is not None else 999):
            entry.update(best)

    rows = sorted(cities.values(), key=lambda r: r["score"])
    return [{k: r[k] for k in ("city", "name", "load", "tier", "score", "tags", "count")}
            for r in rows[:limit]]


def answer(argv):
    """The value to print for these arguments."""
    if len(argv) < 2:
        return []
    servers, tier = read_servers()
    if argv[1] == "--cities":
        # MaxTier is the signed-in account's tier as of the client's last
        # fetch (0 is Free). `protonvpn info` doesn't print the plan, and this
        # file is already being read, so it rides along with the cities.
        return {"maxTier": tier, "cities": all_cities(servers) if servers else []}
    if argv[1] == "--locate":
        name = argv[2] if len(argv) > 2 else ""
        return locate(servers, name) if (servers and name.strip()) else {}
    if servers is None:
        return []
    try:
        limit = max(1, min(500, int(argv[2]))) if len(argv) > 2 else 80
    except ValueError:
        limit = 80
    return country_cities(servers, argv[1].strip().upper(), limit)


def main():
    empty = "{}" if len(sys.argv) > 1 and sys.argv[1] in ("--cities", "--locate") else "[]"
    try:
        # allow_nan=False: NaN and Infinity are not JSON and the panel's
        # parser refuses them, so they must never be printed.
        out = json.dumps(answer(sys.argv), separators=(",", ":"), allow_nan=False)
    except Exception:  # noqa: BLE001 - a helper that prints a traceback is a broken panel
        out = empty
    print(out)


if __name__ == "__main__":
    main()
