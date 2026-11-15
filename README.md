# libeo

The shared library for the e-scripts on Lich 5. One loader,
`scripts/libeo.lic`, over a directory of small files, `scripts/eo/`, each
about one thing and readable on its own.

```
Script.loadlib('libeo')         how a script loads it, once per session
EO.require('0.9.0')             the version the script was built against
EO.use(command: ..., wait: ...)  the script's own helpers, lent to the library
```

## What is in it

| File | What it holds |
|---|---|
| `eo/version.rb` | `EO.require` and `EO.version`, the version gate |
| `eo/helpers.rb` | `EO.use`: a script lends its own helpers; `EO.command`, `EO.result`, `EO.settle`, `EO.go2` and `EO.say` call the running script's |
| `eo/containers.rb` | `EO::Containers`: whether Lich has a container's contents, opening one that does not, waiting for contents, reading them fresh, closing |
| `eo/hands.rb` | `EO::Hands`: what the hands hold, freeing one, taking an item, wearing one, putting one in a container, the READY list's STORE and READY; every outcome comes back as a word |
| `eo/town.rb` | `EO::Town`: which shop to walk to and whether to go at all, a shop in a bounty's town within the region, Four Winds Isle and the way off it, the trash receptacle, the locksmith pool's worker |
| `eo/items.rb` | `EO::Items`: throwing an item away unless it is marked, phasing a box and bringing it back, lifting a curse, waiting for the disk |
| `eo/boxes.rb` | `EO::Boxes`: opening a box, looking in, taking its coins, which emptied box is kept |
| `eo/stow.rb` | `EO::Stow`: the bags an item is tried in by the STOW list, and the bags to open before looting |
| `eo/loot.rb` | `EO::Loot`: what in a room is no loot, whether an item is wanted, searching a dead creature |
| `eo/skinning.rb` | `EO::Skinning`: which dead to skin and with what kind of tool, getting ready, the skinning, standing up after |
| `eo/selling.rb` | `EO::Selling`: selling one item to a shop, asking a shop what an item is worth |
| `eo/locksmith.rb` | `EO::Locksmith`: the town locksmith (how he is called, his fee, the pay) and the locksmith pool (the drop-off order, the give, the return, the pool's depth, the rising tip) |
| `eo/locker.rb` | `EO::Locker`: which rooms hold a character's locker, the last step into a booth, a debt, opening the locker and finding the stash in it |
| `eo/hoard.rb` | `EO::Hoard`: hoarding gems and reagents in jars: label names, the kind check, a stash's inventory by looking or from a premium locker's manifest, shaking a jar |
| `eo/casting.rb` | `EO::Casting`: the multicast count, one cast and what its answer means, having the mana or stamina for it (Sign of Wracking, Sigil of Power, Symbol of Mana), another character's active spells, manna bread |
| `eo/cleanse/tables.rb` | `EO::Cleanse`: the debuffs and room hazards by name, the spell a character has for each job, TARGET and its answers, the mana pulse |
| `eo/cleanse/hazards.rb` | `EO::Cleanse::Hazards`: a web, globe or cloud got rid of by spell, Spell Cleave or Spell Thieve; acidic mist blown away; a runestone broken |
| `eo/cleanse/traps.rb` | `EO::Cleanse::Traps`: the Hive's traps searched out and disarmed; the itchy curse's safe place and wait |
| `eo/cleanse/disarms.rb` | `EO::Cleanse::Disarms`: a weapon back in hand, the list of disarms not yet recovered (kept across restarts), reading RECOVER ITEM |

What lives here is script-side glue that Lich itself should not carry.
Anything that is a game rule or parser plumbing belongs in Lich and is called
directly; a script that needs it raises its required Lich version.

## Installing

libeo needs Lich 5.22.0 or later. It ships as a gem that carries the
library and an installer:

```
gem install libeo-<version>.gem
libeo install            # copies libeo.lic and eo/ into Lich's scripts/
libeo doctor             # what is installed and whether it is intact
libeo uninstall
```

Lich is found from `--lich-dir PATH`, else the `LICH_DIR` environment
variable, else the usual install places. From a checkout,
`ruby exe/libeo install --lich-dir PATH` does the same.

The installer records what it put there, so an upgrade removes files a newer
version dropped and an uninstall removes exactly what was installed.

## Developing

```
bundle install
bundle exec rspec        # the library's specs and the installer's
bundle exec rubocop
bundle exec rake gem     # builds dist/libeo-<version>.gem
```

The specs stand in for Lich's globals with small fakes; nothing needs a
running Lich. A tag `v<version>` builds the gem and attaches it to a GitHub
release.
