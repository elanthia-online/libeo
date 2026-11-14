# libeo

The shared library for the e-scripts on Lich 5. One loader,
`scripts/libeo.lic`, over a directory of small files, `scripts/eo/`, each
about one thing and readable on its own.

```
Script.loadlib('libeo')         how a script loads it, once per session
EO.require('0.24.0')             the version the script was built against
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
| `eo/cleanse/tables.rb` | `EO::Cleanse`: the debuffs and room hazards by name, the spell a character has for each job, TARGET and its answers |
| `eo/cleanse/hazards.rb` | `EO::Cleanse::Hazards`: a web, globe or cloud got rid of by spell, Spell Cleave or Spell Thieve; acidic mist blown away; a runestone broken |
| `eo/cleanse/traps.rb` | `EO::Cleanse::Traps`: the Hive's traps searched out and disarmed; the itchy curse's safe place and wait |
| `eo/cleanse/disarms.rb` | `EO::Cleanse::Disarms`: a weapon back in hand, the list of disarms not yet recovered (kept across restarts), reading RECOVER ITEM |
| `eo/cleanse/afflictions.rb` | `EO::Cleanse::Afflictions`: disease and poison cured, a root or press retreated from, debuffs dispelled, a stun or a web got out of, a room quieted |
| `eo/cleanse/recovery.rb` | `EO::Cleanse::Recovery`: a lost weapon got back: the spirit servant, a bonded weapon, RECOVER ITEM, prying from webbing, a floated weapon, the Sanctum's clench |
| `eo/herbs/table.rb` | `EO::Herbs::Table`: every herb, where it is sold, what it treats and its doses; the stock targets; the two tiers of blood |
| `eo/herbs/injuries.rb` | `EO::Herbs::Injuries`: the herb type a character's wounds call for next, what a dead character or an escort needs |
| `eo/herbs/doses.rb` | `EO::Herbs::Doses::Monitor`: the doses left in each herb and potion, learned from the game as they are used, bought and bundled |
| `eo/herbs/sack.rb` | `EO::Herbs::Sack`: the herb sack: opening it, its contents by form, a Survivalist's Kit's, those of something in the room, putting a herb in and taking one out |
| `eo/herbs/heal.rb` | `EO::Herbs::Heal`: the herb to use for a type, the spells that help, eating or drinking it |
| `eo/herbs/shop.rb` | `EO::Herbs::Shop`: the herbalist's menu, ordering and buying, prices, what a place sells and the sack holds for a heading, bundling |
| `eo/guild/tables.rb` | `EO::Guild::Tables`: the Adventurer's Guild's towns, people and their rooms, what they say, and the kinds of task by name |
| `eo/guild/npcs.rb` | `EO::Guild::NPCs`: someone in the room by name, the taskmaster to ask (Seldit searched for on Sailor's Grief), a town's guard rooms |
| `eo/guild/location.rb` | `EO::Guild::Location`: a task's place as a start room and boundaries, cut down to a connected part when large; a room id from a map id or a uid |
| `eo/guild/taskmaster.rb` | `EO::Guild::Taskmaster`: get, turn in, remove and expedite a task; boosts and vouchers |
| `eo/guild/assignments.rb` | `EO::Guild::Assignments`: the furrier, herbalist and gem dealer visits, and the guards', a found heirloom in hand |
| `eo/guild/vetting.rb` | `EO::Guild::Vetting`: whether a task is one the character takes |
| `eo/guild/completion.rb` | `EO::Guild::Completion`: the rule a hunting script stops on when a task is done enough; counting the skins and gems held for a task |
| `eo/guild/forage.rb` | `EO::Guild::Forage`: where a herb grows, the spells and readying before a try, the try and its answers, putting the find away, handing herbs to the herbalist |
| `eo/guild/heirloom.rb` | `EO::Guild::Heirloom`: the heirloom search: the spells before it, the search and what it turns up, the step to the next room |
| `eo/guild/escort.rb` | `EO::Guild::Escort`: an escort task and its towns, having the client follow, and the walk: keeping the room clear, hiding and hasting, a step along the path and a step back |
| `eo/guild/escort_routes.rb` | `EO::Guild::Escort::ROUTES`: the hard parts of the escort roads, each as the walk takes it |
| `eo/guild/disablers.rb` | `EO::Guild::Disablers`: spells that stop creatures without killing them: which can be cast now, the best for what is in the room, the cast |
| `eo/guild/rescue.rb` | `EO::Guild::Rescue`: a lost child: finding it, where it lives and the guards there, a room that is a danger to it, who to report to, the way out of the Maaghara Labyrinth |
| `eo/wander.rb` | `EO::Wander`: one step to the adjacent room visited least recently, by the map or through the Elemental Confluence, and finding and targeting a creature by name |

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
