# libeo

The shared library for the e-scripts on Lich 5. One loader,
`scripts/libeo.lic`, over a directory of small files, `scripts/eo/`, each
about one thing and readable on its own.

```
Script.loadlib('libeo')         how a script loads it, once per session
EO.require('0.60.0')             the version the script was built against
```

## What is in it

| File | What it holds |
|---|---|
| `eo/version.rb` | `EO.require` and `EO.version`, the version gate |
| `eo/command.rb` | `EO.command`, `EO.result`, `EO.settle`, `EO.stand`, `EO.kneel`: a command and its answer, sent again after roundtime; waiting roundtime out; standing up and kneeling down, a few tries at most |
| `eo/messages.rb` | `EO.say`, `EO.word_wrap`: a message in one of Lich's colours |
| `eo/travel.rb` | `EO.go2`, `EO.at?`, `EO.nearest`, `EO.visit`, `EO.wander`, `EO.room_id`, `EO.fwi?`, `EO.fog_wanted?`: walking and where the character is |
| `eo/scripts.rb` | `EO.run_scripts`, `EO.split_script`: running a list of scripts with their arguments |
| `eo/help.rb` | `EO.help`: a script's table of commands |
| `eo/settings.rb` | `EO::Settings`: a script's profile file (`load_profile`, `save_profile`), every e-script's settings held for the others to read (`read`), a profile used like CharSettings (`store`), whether Lich can open a setup window (`available?`) |
| `eo/settings/words.rb` | `EO::Settings`: changing one setting from the command line (`update_from_words`, `coerce`, `setting_name`) |
| `eo/settings/table.rb` | `EO::Settings::Registry` and `Listing`: a script's table of settings by category, with defaults, and its printed listing |
| `eo/settings/window.rb` | `EO::Settings::Controls` and `ListForm`: the parts of a setup window the scripts share |
| `eo/containers.rb` | `EO::Containers`: open a container only when it is closed, see one open, read contents the game does not refresh; a carried container is asked of Lich's `Inventory`, the rest by LOOK IN |
| `eo/hands.rb` | `EO::Hands`: free a hand, take an item, wear, put into a container, the READY list; every outcome comes back as a word, over Lich's `Stash` for which hand holds what and opening the way to an item |
| `eo/town.rb` | `EO::Town`: which shop to walk to and whether to go at all, a bounty town's region, Four Winds Isle, the trash can, the locksmith pool's worker, depositing all but the silver to keep |
| `eo/items.rb` | `EO::Items`: toss unless marked, phase and unphase a box, lift a curse, and the disk that follows the character |
| `eo/boxes.rb` | `EO::Boxes`: opening a box, its coins by GET or a coin charm, which emptied box to keep, setting a box on a disk |
| `eo/stow.rb` | `EO::Stow`: where an item goes by the STOW list (its type's bag, the default, the overflow bags in order), which bags are full or, by the inventory feed's weights, lack the room, moving a box to make room, the bags to open before looting, and what a put taught: a bag that closes itself, a crumbly or unlootable item |
| `eo/loot.rb` | `EO::Loot`: the room's non-loot (features, spell effects, disks), which loot a `Policy` wants (read from eloot's settings or built), and searching the dead: LOOT's answers, a find at your feet or in your hand |
| `eo/loot/context.rb` | `EO::Loot::Context`: what a looting pass reads and keeps (the settings, the stow, hands, disk, coin and gambling-kit state, the loot patterns), where it says something and saves what it learned. Nothing uses it yet; the looting code in eloot moves onto it step by step |
| `eo/loot/pickup.rb` | `EO::Loot::Pickup`: picking up one item for a looting pass: a box into a disk, an item into the first bag on its route, a box moved aside when none has room (it answers :stored, :no_room or :no_default and leaves what to do about a full pack to the caller), and LOOT into its bag |
| `eo/loot/floor.rb` | `EO::Loot::Floor`: the looting of a room, its boxes and its bags: coins, cursed items, orbs and keepers one by one, the ordinary items by LOOT ROOM or by hand, the boxes lying in a room, and the policy that says what is loot; each item goes through the caller's drag, so a full pack stays the caller's |
| `eo/loot/pass.rb` | `EO::Loot::Pass`: one looting pass over a room a step at a time (start, step, finish, run): skin the dead, search them, loot the floor, give the hands back; a step ends with what it handled put away, and says :no_room when it could not |
| `eo/loot/handler.rb` | `EO::Loot::Handler`: what a looting pass does with the hands and the bags (free a hand, draw an item, put it away, open the bags, give the hands back); it never pauses or ends the script, and answers :full, :no_default, :crippled or :overloaded for the caller to act on |
| `eo/loot/hooks.rb` | `EO::Loot::Hooks` and `EO::Loot.build`: the standard hooks of a looting pass the way eloot has them (commands and their roundtime retries, the sell inventory, the disk, decurse, toss, unlootable, stance), what the character carries, and a pass ready to run for a script that is not eloot |
| `eo/skinning.rb` | `EO::Skinning`: who needs a blunt tool, which dead to skin and with which tool, the tool drawn and put back, getting ready, the skinning and what it learned, standing up after |
| `eo/skinning/pass.rb` | `EO::Skinning::Pass`: the skinning of a looting pass a tool group at a time (start, step, finish, run): which dead take which tool, the tool drawn and put away, what the game said cannot be skinned; the hands are free between steps |
| `eo/selling.rb` | `EO::Selling`: sell one item at a shop: sold, refused or kept |
| `eo/locksmith.rb` | `EO::Locksmith`: the town locksmith (activator, open, fee) and the locksmith pool (box order, incremental tips, the give, the list and depth, taking boxes back) |
| `eo/locker.rb` | `EO::Locker`: the character's locker rooms, getting into a booth (taken, elsewhere, a debt), opening it to a container, leaving |
| `eo/hoard.rb` | `EO::Hoard`: hoarding gems and reagents in jars: label names, the kind check, reading a jar, the stash inventory by looking or from a premium locker manifest, filling and shaking |
| `eo/appraisal.rb` | `EO::Appraisal`: ask a shop what an item is worth and read the answer |
| `eo/casting.rb` | `EO::Casting`: casting a spell at a target and reading the answer (hindrance retried, with a recheck before each retry), the multicast limit, making mana by a society's power or waiting for it (`Resources`), stamina, another character's active spells, manna bread summoned, eaten and dropped |
| `eo/cleanse/tables.rb` | `EO::Cleanse`: the dispellable debuffs, the hazards and TARGET's answers, the `Policy`, the spell this character has for a job, whether the wounds allow a cast (the Sigil of Determination cast when it helps) |
| `eo/cleanse/hazards.rb` | `EO::Cleanse::Hazards`: clouds, magic globes, webs and runestones in the room: find one, target it, dispel, cleave or thieve it (counted only when the game says it hit the wards), break a runestone |
| `eo/cleanse/afflictions.rb` | `EO::Cleanse::Afflictions`: poison and disease, magical debuffs, a root or press, a stun, a web or bind, each cured the first way the policy allows; settling a room before a recovery |
| `eo/cleanse/disarms.rb` | `EO::Cleanse::Disarms`: the disarms not yet recovered, kept across restarts; RECOVER ITEM searching, a bonded weapon's return, the spirit servant, prying a webbed weapon, a floated weapon, the Sanctum's clench |
| `eo/cleanse/traps.rb` | `EO::Cleanse::Traps`: hive traps searched out and disarmed, the itchy curse's safe room and wait, the Sanctum vat |
| `eo/herbs/table.rb` | `EO::Herbs::Table`: every herb: where it is sold, its name, the wound it cures, a shop menu's short name, the doses a bought one holds |
| `eo/herbs/injuries.rb` | `EO::Herbs::Injuries`: the next herb type a character's wounds want, by the worst first or only what stops casting; another character's wounds from APPRAISE; an escort's from LOOK |
| `eo/herbs/doses.rb` | `EO::Herbs::Doses`: the doses left in each item, counted from what the game says as herbs are eaten, measured, poured, bought and bundled |
| `eo/herbs/sack.rb` | `EO::Herbs::Sack`: the herb sack: finding it, opening and reading it, a Survivalist's Kit, taking an herb out and putting it back |
| `eo/herbs/heal.rb` | `EO::Herbs::Heal`: healing with herbs until nothing is left to heal or to heal with; handing herbs to the dead and to an escort |
| `eo/herbs/shop.rb` | `EO::Herbs::Shop`: the herbalist's menu and prices, buying, bundling, what is in stock and stocking to a count or a share of the kit |
| `eo/guild/tables.rb` | `EO::Guild::Tables`: the Adventurer's Guild's towns, people and their rooms, what they say, and the kinds of task by name; `EO::Guild::Error`, raised where a task cannot go on |
| `eo/guild/policy.rb` | `EO::Guild::TaskPolicy`: which tasks a character takes, and why one is handed back |
| `eo/guild/npcs.rb` | `EO::Guild::NPCs`: someone in the room by name, the taskmaster to ask (Seldit searched for on Sailor's Grief), a town's guard rooms |
| `eo/guild/location.rb` | `EO::Guild::Location`: a task's place as a start room and boundaries, cut down to a connected part when large |
| `eo/guild/forage.rb` | `EO::Guild::Forage`: where a herb grows, FORAGE SENSE's slots left, the foraging loop and its steps one at a time, handing herbs to the herbalist |
| `eo/guild/taskmaster.rb` | `EO::Guild::Taskmaster`: get, turn in, remove and expedite a task; boosts, vouchers, the wait for the next task |
| `eo/guild/assignments.rb` | `EO::Guild::Assignments`: the furrier, herbalist and gem dealer visits that set a task |
| `eo/guild/guards.rb` | `EO::Guild::Guards`: the guard visit that sets or completes a task, a found heirloom in hand |
| `eo/guild/completion.rb` | `EO::Guild::Completion`: the `Rule` for when a task is done enough to go to town; counting the skins and gems held for a task, a bundle's count kept between MEASUREs |
| `eo/guild/heirloom.rb` | `EO::Guild::Heirloom`: the heirloom search (the walk, SEARCH, putting the find away) and the helper spells foraging shares |
| `eo/guild/escort_routes.rb` | `EO::Guild::Escort::ROUTES`: the hard parts of the escort roads: climbs, the Darkstone sneaks, the mining carts, the ferry, the misty trail |
| `eo/guild/escort.rb` | `EO::Guild::Escort`: the escort: the trip from the task, fetching the client, the road, the room checks and the ambush watch |
| `eo/guild/disablers.rb` | `EO::Guild::Disablers`: choosing and casting a spell that stops what is met on a walk without killing it |
| `eo/guild/rescue.rb` | `EO::Guild::Rescue`: the lost child: finding it, its home, the walk to a guard, the way out of the Maaghara Labyrinth; running a rescue script with its retries |
| `eo/wander.rb` | `EO::Wander`: a step from wherever the character is (the Elemental Confluence its own way, anywhere else `EO.wander`), the first live creature of a list of names, whether it is hostile, targeting it and learning what TARGET accepts |
| `eo/brooch.rb` | `EO::Brooch`: the quintuple orb brooch: rubbing an orb, or chaos when it gives that orb, with the day's rubs tallied so ANALYZE is seldom asked; `EO.eastern_day` |
| `eo/chain.rb` | `EO::Chain`: chaining bounties: the rubs before a turn-in, one reducer after it when the head is over its cap, and the chaos roll when a gem or heirloom task starts |
| `eo/carry.rb` | `EO::Carry`: what the character can carry before encumbrance and what it carries now, from the formula, the inventory feed's weights and a correction learned from the encumbrance bar; the floating disk's limit |
| `eo/coordination/` | `EO::Coordination`: opt-in coordination between independent Lich sessions: a bounded loopback transport, read-only observations, discovery, explicitly granted operations, a parser projection. Loading it starts nothing (from eohunter's libeocoordination) |

What lives here is script-side glue that Lich itself should not carry.
Anything that is a game rule or parser plumbing belongs in Lich and is called
directly; a script that needs it raises its required Lich version.

## The scripts

The e-scripts that use the library are here too, each as it stands on
the library: what moved out of it is gone from the script, and what is
left is its settings, its command line and its own flow.

| Script | Version | What it asks of the library |
|---|---|---|
| `scripts/eloot.lic` | 2.18.7 | `EO::Appraisal`, `EO::Boxes`, `EO::Carry`, `EO::Containers`, `EO::Hands`, `EO::Hoard`, `EO::Items`, `EO::Locker`, `EO::Locksmith`, `EO::Loot`, `EO::Selling`, `EO::Settings`, `EO::Skinning`, `EO::Stow`, `EO::Town` |
| `scripts/ebounty.lic` | 1.16.2 | `EO::Containers`, `EO::Guild`, `EO::Settings`, `EO::Town`, `EO::UnknownRoom` |
| `scripts/echild.lic` | 1.23.2 | `EO::Guild::Disablers`, `EO::Guild::Rescue`, `EO::Settings` |
| `scripts/escortgo2.lic` | 1.3.0 | `EO::Guild`, `EO::Guild::Escort`, `EO::Settings` |
| `scripts/ewaggle.lic` | 2.5.1 | `EO::Casting`, `EO::Loot`, `EO::Settings` |
| `scripts/ecleanse.lic` | 2.7.1 | `EO::Cleanse`, `EO::Settings` |
| `scripts/eherbs.lic` | 2.6.1 | `EO::Guild`, `EO::Herbs`, `EO::Settings`, `EO::Town` |
| `scripts/ewander.lic` | 2.3.0 | `EO::Settings`, `EO::Wander` |

`spec/scripts_spec.rb` checks that every `EO` method a script names is
one the library has. The installer does not copy the scripts; they are
installed as scripts are.

Where a script behaves differently from the one in `elanthia-online/scripts`
is listed, script by script, in [docs/behaviour-changes.md](docs/behaviour-changes.md).

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
