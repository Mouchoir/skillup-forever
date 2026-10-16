#!/usr/bin/env python3
"""Print a translation template with every L["..."] phrase in the shipped Lua.

Writes nothing: `python3 tools/phrases.py > Locales/phrases.txt`. A translator copies that file to
Locales/<locale>.lua and translates the right-hand sides (Locales/README.md).
"""

import re
from pathlib import Path

from typecheck_coverage import runtime_files

ROOT = Path(__file__).resolve().parent.parent
HEADER = """\
-- Every phrase SkillUp shows, with its English text: the template the Locales/<locale>.lua files follow.
-- Each client language already has its file; to correct a line, edit that file (Locales/README.md).
local _, ns = ...
if GetLocale() ~= "deDE" then
\treturn
end
local L = ns.L
"""
# The phrase as written in the source, escapes included, so it pastes back into Lua unchanged.
PHRASE = re.compile(r'\bL\["((?:\\.|[^"\\\n])*)"\]')


def phrases() -> list[str]:
    found = set()
    for path in runtime_files(ROOT):
        # A translation's keys are this template's own phrases: reading them would keep a removed one alive.
        if path.parent.name == "Locales":
            continue
        found.update(PHRASE.findall(path.read_text()))
    return sorted(found)


if __name__ == "__main__":
    print(HEADER)
    for phrase in phrases():
        print(f'L["{phrase}"] = "{phrase}"')
