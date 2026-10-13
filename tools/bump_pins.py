#!/usr/bin/env python3
"""Move each generator pin to its newest upstream and print what moved, one line (stdlib only).

Prints nothing when every pin is current. CLASSICDB_COMMIT is a named waiver in AGENTS.md and stays.
"""

import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from latest_build import USER_AGENT, forever, newest

TOOLS = Path(__file__).resolve().parent
BUILD = re.compile(r"\d+(\.\d+){3}")
COMMIT = re.compile(r"[0-9a-f]{40}")


def fetch(url):
    headers = {"User-Agent": USER_AGENT}
    # The API allows an address 60 requests an hour without a token; a workflow passes its own.
    if url.startswith("https://api.github.com/") and os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
        return response.read()


def file_commit(repository, path):
    """The pin for one file of an upstream repository: it moves only when the file's bytes do."""

    def latest(pinned):
        query = urllib.parse.urlencode({"path": path, "per_page": 1})
        commit = json.loads(fetch(f"https://api.github.com/repos/{repository}/commits?{query}"))[0]["sha"]
        raw = f"https://raw.githubusercontent.com/{repository}/{{}}/{urllib.parse.quote(path)}"
        if commit != pinned and fetch(raw.format(commit)) == fetch(raw.format(pinned)):
            return pinned
        return commit

    return latest


# Pin name: the generator that holds it, the label a pull request shows, the value's shape and its upstream.
PINS = {
    "BUILD": ("gen_thresholds.py", "Forever", BUILD, lambda _: forever()),
    # Classic Era builds are 1.1x.
    "TEACH_BUILD": ("gen_thresholds.py", "Classic Era", BUILD, lambda _: newest("wow_classic_era", "1.1")),
    "PT_COMMIT": (
        "gen_vendor.py",
        "LibPeriodicTable",
        COMMIT,
        file_commit(
            "doadin/libperiodictable-3-1", "LibPeriodicTable-3.1-Tradeskill/LibPeriodicTable-3.1-Tradeskill.lua"
        ),
    ),
}


def repin(source, name, value):
    """source with the module-level `name = "..."` set to value, and the value it held."""
    line = re.compile(rf'^{name} = "([^"]*)"$', re.MULTILINE)
    found = line.findall(source)
    if len(found) != 1:
        raise SystemExit(f"expected one {name} pin, found {len(found)}")
    return line.sub(f'{name} = "{value}"', source), found[0]


def main():
    moved = []
    for name, (filename, label, shape, latest) in PINS.items():
        path = TOOLS / filename
        source = path.read_text(encoding="utf-8")
        _, pinned = repin(source, name, "")
        value = latest(pinned)
        if not shape.fullmatch(value):
            raise SystemExit(f"{name}: upstream gave {value!r}")
        if value == pinned:
            print(f"{name}: already on {pinned}", file=sys.stderr)
            continue
        path.write_text(repin(source, name, value)[0], encoding="utf-8")
        moved.append(f"{label} {value[:12]}")
    if moved:
        # The date the snapshot was selected, which the generated headers carry.
        path = TOOLS / "gen_thresholds.py"
        today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
        path.write_text(repin(path.read_text(encoding="utf-8"), "SOURCE_DATE", today)[0], encoding="utf-8")
        print(", ".join(moved))


if __name__ == "__main__":
    main()
