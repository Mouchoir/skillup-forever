# Translations

SkillUp is written in English, and every phrase it shows goes through `L["..."]`, so a phrase nobody has
translated just stays English.

It ships in every language the WoW: Forever client has besides English: deDE, esES, esMX, frFR, koKR, ptBR, ruRU,
zhCN and zhTW (the client has no Italian). Those files are machine translated, using the game's own words for
professions, trainers, reagents and the rest, and say so on their first line. Some frFR lines are Brainc3ll's, from
Legacy Forever; in that file each machine line ends `-- mt`. A human line always wins over a machine one.

To correct a line, change the text on the right in `<locale>.lua` and remove its `-- mt` if it has one. In a file
that is all machine translated, the first correction makes it mixed: every line you didn't touch then gets `-- mt`,
so a later machine pass only ever replaces marked lines. Keep the
`%d` and `%s` bits; `%2$s` style numbering works if your word order needs it. Then open a pull request, or paste
the lines into the [translation form](https://github.com/cjber/skillup-forever/issues/new?template=translation.yml)
and I'll add them.

New phrases land in `phrases.txt` (`python3 tools/phrases.py > Locales/phrases.txt`), the template with every
phrase and its English text. `python3 tools/check_locales.py` checks each file against it and prints each
language's coverage.
