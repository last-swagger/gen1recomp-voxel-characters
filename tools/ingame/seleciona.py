# WRITE ONE MOD SELECTION INTO options.lua, FOR ONE GAME.
#
#   python3 seleciona.py <options.lua> <ids to enable> <ids to answer for> <game>
#
# Both id lists are whitespace- or comma-separated. "ids to answer for" is
# every id this caller is willing to be responsible for: they are all written
# out as false first, and then the enable list is written true on top. Anything
# not in either list is left exactly as the player had it.
#
# Lifted out of tools/ingame/hosts.sh so tools/ingame/gold.sh could use the
# same code instead of a second copy. hosts.sh answers for the five voxel
# hosts; gold.sh answers for every mod installed on the machine, because a gate
# that walks the player has to pin what else is running. The comments below are
# the ones that were in hosts.sh, and every one of them is a paid error.
#
# The caller is responsible for backing options.lua up and restoring it: this
# script only ever writes the selection it was asked for.
import re
import sys

path, want, known, game = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
wants = [w for w in re.split(r"[\s,]+", want) if w]
known = [k for k in re.split(r"[\s,]+", known) if k]
src = open(path, encoding="utf-8").read()

# Any override already in the file goes FIRST, before anything else is located
# or written: a force left over from the previous row would otherwise still be
# in the file while this row ran, and a Gold row's override surviving into a
# Blue row is the kind of leak that makes a matrix measure something other than
# what it prints. Stripping it up front also means the block below is always
# inserted into a file with exactly one known shape.
#
# BOTH SERIALISED SHAPES, and the empty one is the one that bites: the engine
# writes `modsGen2 = {},` on a single line when the table is empty, which the
# block pattern does not match. Leaving it there put a SECOND modsGen2 key in
# the same Lua table after the one written below, and in a table literal the
# last key wins -- so the override read back as nil and the Gold row failed
# with the mod gated out, while the file looked exactly right to the eye.
src = re.sub(r"\n  modsGen2 = \{\},\n", "\n", src)
src = re.sub(r"\n  modsGen2 = \{\n.*?\n  \},\n", "\n", src, flags=re.S)

# Drop the per-game overlay for the mods this caller controls, so the shared
# `mods` block below is what decides for them again. Only those ids are
# touched: every other per-game choice in there is the player's and has to
# survive, and options.lua is restored byte for byte by the caller regardless.
#
# SaveData.modEnabled reads options.modsByVersion[game][id] FIRST and only
# falls through to mods[id] when that is absent, so a per-game overlay silently
# outranks everything written here. The overlay is not usually in a fresh
# options.lua -- it is created by the engine's own one-time migration, which
# fires on the FIRST boot and copies the then-current answers to every game.
# Inside a matrix that boots more than once that is a trap with teeth: row 1
# persists an overlay built from row 1's selection, and every later row is then
# measured against row 1's hosts no matter what it wrote. It cost a full red
# Gold row to find.
gerido = set(known) | set(wants) | {"voxel_characters"}
mbv = re.search(r"\n  modsByVersion = \{\n.*?\n  \},\n", src, re.S)
if mbv:
    mantidas = []
    for linha in mbv.group(0).split("\n"):
        alvo = re.match(r"\s*([\w_]+) = (?:true|false),\s*$", linha)
        if alvo and alvo.group(1) in gerido:
            continue          # this id is the caller's to answer for
        mantidas.append(linha)  # a bucket header, a brace, or someone else's mod
    src = src[:mbv.start()] + "\n".join(mantidas) + src[mbv.end():]

m = re.search(r"\n  mods = \{\n(.*?)\n  \},\n", src, re.S)
if not m:
    sys.exit("could not find the mods block in options.lua")
entries = {}
for line in m.group(1).split("\n"):
    em = re.match(r"\s*([\w_]+) = (true|false),\s*$", line)
    if em:
        entries[em.group(1)] = em.group(2)
# Only `false` disables a mod (src/mods/Loader.lua:156): a mod merely left out
# of the list counts as ENABLED, so every id the caller answers for has to be
# written out as false explicitly before the wanted ones are turned back on.
# Getting this wrong makes the run measure the wrong set and still look like it
# worked.
for h in known:
    entries[h] = "false"
for h in wants:
    entries[h] = "true"
body = "\n".join("    %s = %s," % (k, v) for k, v in sorted(entries.items()))
block = "\n  mods = {\n" + body + "\n  },\n"

# MEASURING GEN 2 WITHOUT CLAIMING IT. Our manifest says games: ["gen1"], so on
# a Gen 2 game the loader gates this mod out before it can look for a host
# (src/mods/Loader.lua:_gateGeneration). The player's own per-game override --
# the manager's TRY HERE ANYWAY toggle, options.modsGen2[id][version] -- forces
# it on for one boot and marks it "not verified by its author", which is
# precisely what is true today.
#
# Widening the manifest instead would make the gate pass by assertion: the
# claim that this mod runs on Gold is the thing being measured, so it cannot
# also be the input. The override is a no-op the day the claim is real --
# _gateGeneration consults it only AFTER ModTargets.supports says no -- so this
# line does not have to be removed when the manifest grows.
force = ""
if game != "blue":
    force = ("  modsGen2 = {\n    voxel_characters = {\n"
             "      %s = true,\n    },\n  },\n" % game)
open(path, "w", encoding="utf-8").write(src[:m.start()] + block + force + src[m.end():])
