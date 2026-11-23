#!/usr/bin/env python3
"""List installed apps as split-tunneling candidates, for the panel's picker.

Proton matches split-tunnelled processes by executable path, with a prefix
test that also covers a matched process's children. So the panel needs a real
path on disk for every app it offers, not a desktop-entry name, and it must
never offer a path that would sweep in far more than the app asked for.

Desktop entries are the only list of "apps a person recognises" the system
keeps, so they are the source here. Each entry's Exec line is reduced to its
program, resolved against PATH, and kept only if it is a file we can execute.

Two kinds of entry are deliberately dropped:

  * Flatpak and Snap launchers. Their Exec is the sandbox runner, so the path
    on disk is /usr/bin/flatpak, shared by every Flatpak app. Excluding one
    would silently exclude all of them. Matching a sandboxed app needs its
    real binary, which the entry does not name.
  * Anything that resolves to a shell, since a prefix match on /usr/bin/bash
    would catch most of the session, and anything that runs as another user,
    for the same reason.
  * Launcher stubs. Entries that go through hyprctl, uwsm, a terminal chooser
    or Omarchy's web-app handlers name the dispatcher, not the app, and the
    dispatcher has usually handed off to something else by the time the app
    opens a socket. Offering them would promise an exclusion that never fires.

Usage: apps.py            every candidate app, JSON, sorted by name
Prints [{"value": <path>, "label": <name>, "description": <path>}, ...].
"""
import json
import os
import shlex
import stat
import sys

# Exec lines carry these placeholders for files and URLs; none survive here.
FIELD_CODES = {"%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N",
               "%i", "%c", "%k", "%v", "%m"}

# Runners whose path says nothing about which app is being launched.
SANDBOX_RUNNERS = {"flatpak", "snap", "flatpak-spawn"}
SHELLS = {"sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "env",
          "gtk-launch", "xdg-open"}
DISPATCHERS = {"hyprctl", "uwsm", "xdg-terminal-exec", "dbus-launch"}
DISPATCHER_PREFIXES = ("omarchy-launch-", "omarchy-webapp-handler-")
# Programs that run something else: the path on disk is shared by everything
# started through them, so it names no one app. Matched with any version
# suffix, python3.14 as well as python.
RUNTIMES = ("python", "pypy", "perl", "ruby", "node", "nodejs", "bun", "deno",
            "java", "lua", "luajit", "php", "mono", "dotnet", "wine",
            "electron", "nice", "nohup", "setsid", "timeout", "stdbuf",
            "ionice", "chrt")

# A desktop entry is a few hundred bytes; this is far past any real one.
ENTRY_LIMIT = 1024 * 1024


def generic(base):
    """Whether a program name is a shell, runner or runtime, not an app."""
    if base in SANDBOX_RUNNERS or base in SHELLS or base in DISPATCHERS:
        return True
    if base.startswith(DISPATCHER_PREFIXES):
        return True
    stem = base.rstrip("0123456789.-")
    return stem in RUNTIMES


def data_dirs():
    """Every directory that can hold desktop entries, most specific first."""
    home = os.path.expanduser("~")
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    dirs = [data_home]
    raw = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    dirs.extend(d for d in raw.split(":") if d)
    return [os.path.join(d, "applications") for d in dirs]


def parse_entry(path):
    """Returns (name, exec_line) from a .desktop file, or None to skip it."""
    name = None
    exec_line = None
    in_entry = False
    try:
        # A regular file of sane size only: a pipe would block for ever and
        # a device never ends.
        if not os.path.isfile(path) or os.path.getsize(path) > ENTRY_LIMIT:
            return None
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if line.startswith("["):
                    # Only the first group describes the app itself; the
                    # Desktop Action groups after it are separate launchers.
                    if in_entry:
                        break
                    in_entry = line == "[Desktop Entry]"
                    continue
                if not in_entry or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                if key == "Type" and value != "Application":
                    return None
                if key in ("NoDisplay", "Hidden") and value.lower() == "true":
                    return None
                if key == "Name" and name is None:
                    name = value
                elif key == "Exec" and exec_line is None:
                    exec_line = value
    except OSError:
        return None
    if not name or not exec_line:
        return None
    return name, exec_line


def program_of(exec_line):
    """The program a desktop Exec line runs, or None when it is not usable."""
    try:
        parts = shlex.split(exec_line)
    except ValueError:
        return None
    parts = [p for p in parts if p not in FIELD_CODES]
    # Strip leading VAR=value assignments and an `env` wrapper around them.
    while parts and (("=" in parts[0] and not parts[0].startswith("/"))
                     or os.path.basename(parts[0]) == "env"):
        parts.pop(0)
    if not parts:
        return None
    program = parts[0]
    if "\0" in program or generic(os.path.basename(program)):
        return None
    return program


def resolve(program):
    """Absolute path to an executable file, or None."""
    if program.startswith("/"):
        candidate = program
    else:
        candidate = None
        for directory in (os.environ.get("PATH") or "/usr/bin").split(":"):
            if not directory:
                continue
            guess = os.path.join(directory, program)
            if os.path.isfile(guess) and os.access(guess, os.X_OK):
                candidate = guess
                break
    if not candidate:
        return None
    try:
        candidate = os.path.realpath(candidate)
        if not os.path.isfile(candidate) or not os.access(candidate, os.X_OK):
            return None
        # A program that runs as another user is a wrapper around the real
        # app, and a prefix match on it would catch everything launched
        # through it.
        if os.stat(candidate).st_mode & (stat.S_ISUID | stat.S_ISGID):
            return None
    except (OSError, ValueError):
        return None
    # Checked again on the real file: a link named anything can point at a
    # shell or a runtime.
    if generic(os.path.basename(candidate)):
        return None
    return candidate


def collect():
    by_path = {}
    seen_files = set()
    for directory in data_dirs():
        try:
            names = sorted(os.listdir(directory))
        except OSError:
            continue
        for entry in names:
            if not entry.endswith(".desktop") or entry in seen_files:
                continue
            # An entry in a more specific directory shadows the same file
            # name later on, which is how a user override is meant to work.
            seen_files.add(entry)
            parsed = parse_entry(os.path.join(directory, entry))
            if not parsed:
                continue
            name, exec_line = parsed
            program = program_of(exec_line)
            if not program:
                continue
            path = resolve(program)
            if not path:
                continue
            # Several entries can share one binary; the shortest name is
            # nearly always the app itself rather than a variant of it.
            if path not in by_path or len(name) < len(by_path[path]):
                by_path[path] = name
    return by_path


def main():
    try:
        by_path = collect()
    except Exception:  # noqa: BLE001 - a traceback here is an empty picker
        by_path = {}
    apps = [{"value": path, "label": name, "description": path}
            for path, name in by_path.items()]
    apps.sort(key=lambda a: (a["label"].lower(), a["value"]))
    json.dump(apps, sys.stdout, separators=(",", ":"))


if __name__ == "__main__":
    main()
