# Behaviour changes against upstream

Every observable difference between the e-scripts in this repository, which run
on libeo, and the same scripts in `elanthia-online/scripts`. A script that moves
onto a shared library should behave as it did; this is the list of where it does
not, so that each difference can be judged for what it is.

The differences were found by reading both sides method by method. Where a Lich
API is involved it was read in the Lich source (5.24.1). **Nothing here has been
run in the game.**

## What was compared

| Script | Upstream | Here |
|---|---|---|
| eloot | elanthia-online/scripts PR #2578 (2.15.0) | 2.18.2 |
| ebounty | PR #2579 (1.13.0) | 1.16.2 |
| ewaggle | PR #2580 (2.2.0) | 2.5.1 |
| eherbs | PR #2587 (2.3.0) | 2.6.1 |
| ecleanse | PR #2588 (2.4.0) | 2.7.1 |
| echild | main (1.20.4) | 1.23.2 |
| escortgo2 | main (1.0.5) | 1.3.0 |
| ewander | main (2.0.1) | 2.3.0 |

The upstream side of the first five is the open WebUI pull request for each,
since that is the version these were built from. The library is libeo 0.52.1.

`EO::Brooch`, `EO::Chain`, `EO::Carry` and the coordination files are new and no
script upstream had them; they are not listed here.

## How to read the tables

**Kind** says what sort of difference a row is:

| Kind | Meaning |
|---|---|
| fix | upstream did something wrong and this does not |
| rule | a retry count, timeout, default or condition is different |
| swap | the script's own logic is replaced by a Lich API |
| feature | something upstream did not do |
| removed | something upstream did that is gone |
| message | only what is printed differs |
| unclear | a difference in the code whose effect could not be settled by reading |

Two Lich facts sit behind many judgements. `NilClass#method_missing` returns
nil, so most places where upstream called a method on nil did nothing and did
not crash; those are not counted as fixes. `GameObj.loot` and `GameObj.npcs` are
nil when empty.

## Where the differences come from

Most rows trace back to one of eight things. They are worth reading first,
because they are the design of the library and not accidents of the move.

1. **libeo and the Lich floor.** Every script needs libeo and Lich 5.22.0.
   ebounty asked for 5.19.0 and ewaggle for 5.9.0.
2. **One set of command helpers.** Each script had its own `get_command`,
   `get_res` and `wait_rt`, with its own retry rules. They are `EO.command`,
   `EO.result` and `EO.settle` now. A script's debug setting no longer shows or
   logs the commands the library sends; "Wait N sec" and the rash line are not
   retried; an error other than roundtime propagates where some scripts retried
   without end.
3. **Lich's `Bank` and `Currency`** (eloot, ebounty, eherbs). Different
   commands (`deposit all`, `deposit #id`, `withdraw N silver`), three-second
   waits, an explicit handover line needed, free-to-play notes go to the STOW
   default and not the herb sack, Pinefar waits 30 seconds for the banker.
4. **Lich's `Inventory` feed and `Stash`** (eloot, ebounty). A carried container
   is asked of the feed: OPEN only when closed, no LOOK IN, a locked one never
   tried. An item with no id is never "in hand".
5. **Lich's `Injured`, `Stance`, `Mana.pulse`, `CMan`, `Fog` and
   `Combat::Messages`.** Each differs from the script's own test in cases that
   can be named; they are in the shared table and the script tables.
6. **Where settings live.** eherbs, echild, escortgo2 and ewander move from
   CharSettings to a profile file, copied over on the first run. Every script's
   settings are kept in memory for other scripts to read (`EO::Settings.read`).
7. **Public names that are gone.** Methods, data readers and globals another
   script could call no longer exist (`$ego2_my_ambush`, `Ecleanse::Util.*`,
   `EBounty.data.*`, `EHerbs::Inventory`, `ELoot::Hoard.locker_way_in` and
   more). Each script's table has a "removed" row.
8. **Flows that changed shape.** One method became two, or reports differently:
   making mana apart from the cast loop (ewaggle), raise-and-retry in place of
   exit in the guild dialogue (ebounty), the ambush hook (escortgo2), the
   start-up disabler probe apart from the choice (echild), the sack as an object
   (eherbs), settings read once into a policy (ecleanse, eloot).

One thing upstream did is kept on purpose. In eloot every sleep and retry inside
looting was a checkpoint for the room's lease, so a `room_loot` caller could
cancel. The library's sleeps are still checkpoints for eloot: it extends the
modules it loots through with its guarded sleep.

## Known and open

| Script | What | Why it is open |
|---|---|---|
| eloot | A free-to-play withdrawal that the balance cannot cover drains what there is, then exits "Not enough silver" | The behaviour is in Lich's `Bank.withdraw_f2p` |
| eherbs | Free-to-play overflow notes go to the STOW default, not the herb sack | Lich's `Bank`; notes already in the herb sack are still found |
| escortgo2 | In Platinum, portals are no longer deleted from the map. The walk turns `$go2_use_portals` off while it lays a path | A map whose portals do not go by that setting can have a path laid through one |

## Differences shared by several scripts

These recur; the script tables do not repeat the detail.

| Change | Kind |
|---|---|
| libeo is required; an older copy loaded earlier in the session is run again; `EO.require` raises on a mismatch; every e-script's profile is preloaded | feature |
| The Lich check is `Script.require_lich_version!`: a prerelease passes, an unreadable header passes, the banner is reworded, and it runs after libeo loads | swap |
| The version string is `Script.version`: empty, with a "could not find script" line, when the file is not found by name | swap |
| `EO.go2`: waits up to 30 s for another go2, runs up to three times until arrived, warns in an unmapped room | rule |
| `EO.at?` also accepts "1234" and "u1234"; false, not an error, in an unknown room | rule |
| `EO::Settings.save_profile`: creates the directory, unwraps CharSettings proxies, keeps a frozen copy for other scripts | fix + feature |
| An empty profile file falls back to defaults | fix |
| A profile file that cannot be read (cut short, garbled) is moved to `<name>.bad` with a warning that names it, and the script starts on its defaults; a profile is written through a temporary file and renamed | feature |
| `;<script> list` sorts a copy, not the live arrays | fix |
| `;<script> settings`: errors reworded; a decimal value accepted | message + fix |
| The setup class removes its old instance methods on each run | fix |
| `EO.stand` and `EO.kneel`: five tries, where scripts tried until it worked | rule |
| `EO.command` and `EO.result` send a command again only for the whole line "...wait N seconds." (the command did not run). Upstream also did for any "Roundtime: N sec." line, which a command that ran leaves after it, and so could send an action twice | fix |
| `Lich::Gemstone::Mana.pulse`: `waitrt?` first, anchored patterns, 2 s | swap |
| `Injured.able_to_cast?`: one rank-2 arm or hand now casts; eyes totalling 3 now block; rank-1 scars are ignored; sends `_injury` | swap |
| `Stance.change('defensive')`: sends from guarded and under Frenzy; one attempt | swap |
| Messages go through `Lich::Messaging` or `EO.say`: colour and prefix differ | message |

## eloot

### Settings, setup, utilities, bank, travel

| # | Change | Kind |
|---|---|---|
| 1 | `EO.command` is not `get_command`: no debug echo, errors propagate | rule + message |
| 2 | `EO.result` no longer retries on "Wait N sec" or the rash line (the gauntlet in decurse) | rule |
| 3 | Debug lines dropped from Region, `silver_check`, `find_worker` | message |
| 4 | Changing `debug` itself prints no debug lines | rule |
| 5 | Setup window: `disabled` omitted when off; every control recorded in `@refs` (not proven identical) | unclear |
| 6 | `fwi_return` no longer exits when a return room is set without a trinket | fix |
| 7 | `Region.furrier` / `gemshop`: the first matching town; an empty town name matches no town (upstream crashed) | rule + fix |
| 8 | `silver_check` is `Currency.silver(refresh: true)`: sends `wealth`, a stale value on a miss | swap |
| 9 | `silver_deposit` through `EO::Town.keep_silver`: checks it reached a bank, and warns of a refused deposit or a short withdrawal | fix + swap |
| 10 | Deposit commands: `withdraw N silver`, 3 s waits, the Pinefar banker wait, the debt notice handled | swap |
| 11 | A free-to-play deposit is Lich's: `withdraw N note`, the note to the STOW default, stops when nothing is carried | swap |
| 12 | Free-to-play with no bank access: upstream crashed on a bad `msg` call; now prints and exits, for any deposit that came to nothing | fix + rule |
| 13 | A free-to-play keep-silver withdrawal can pull notes from STOW | swap |
| 14 | Free-to-play inside Bank is `Account.type == 'FREE'`, with no test-server exemption | swap |
| 15 | `f2p?` is `Bank.f2p?` (Infomon), not `Account.subscription` | swap |
| 16 | `silver_withdraw` through `Bank.withdraw` (see Known and open) | swap |
| 17 | `deposit_note` sends `deposit #<id>`, 3 s; nothing at Pinefar | swap |
| 18 | `read_note` returns 0, not nil, with no note | swap |
| 19 | Disk hook: a "disintegrates" line clears the handle only for the script's own disk, and waits a second at most; "arrives" always replaces it | rule |
| 20 | `wait_for_disk` no longer pushes the disk onto `sell_containers`; asks the feed on each call | swap + rule |
| 21 | `fresh_contents` skips LOOK IN for a carried container the feed knows | swap |
| 22 | The `decurse` pulse is `Mana.pulse(315)` | swap |
| 23 | Edge fixes: `find_trash` answers nil, not the raw lines; a nil `GameObj.npcs` is tolerated; `fwi?` is false for nil | fix |

### Inventory, Hoard, Loot

| # | Change | Kind |
|---|---|---|
| 24 | `drag` opens closed parents first (`Stash.open_path_to`) | swap + feature |
| 25 | `drag` waits up to 3 s for the drag's own answer (taken, missing, too heavy) | rule |
| 26 | `free_hand` exits when neither arm is usable (the branch could not be reached upstream) | fix |
| 27 | "In hand" through `Stash`: an item with no id is never in hand | swap |
| 28 | `container_contents`: two retry messages gone; the "wide leather belt" answer dropped | message + rule |
| 29 | `open_single_container` asks the feed: OPEN only when closed, never LOOK IN, a locked one gets no command | swap |
| 30 | A bag opened in the middle of a put is not remembered for closing | rule |
| 31 | A sheath is opened by the feed's flag; a refresh on every sheath STORE | swap |
| 32 | A bag found closed is not learned as an auto-closer under the feed; it is one the script opened within the minute and did not close | rule |
| 33 | A put is skipped when the bag lacks the room by weight | feature |
| 34 | A box is moved aside to make room before pausing for full bags | feature |
| 35 | The weights are dropped after an unpause and at the end of the pass | feature |
| 36 | A disk full by its item count or 500 lbs is not tried | feature |
| 37 | `wear` returns true where it returned nil; waits for a `^You` line | unclear |
| 38 | `open_locker`: 3 attempts (was 4), OPEN LOCKER once, retry messages gone | rule + message |
| 39 | The locker entrance message names the booth, not the room outside | message |
| 40 | Jar lookup escapes the name; shake compares ids exactly | fix |
| 41 | A premium manifest with a container it does not list no longer raises | fix |
| 42 | Box coins: a deposit that frees nothing stops the loop and keeps the box | fix |
| 43 | Coin charm: five tries, then exit; silver counted once | rule + fix |
| 44 | Ground box: an unknown GET COINS answer leaves the coins and carries on | fix |
| 45 | Silver read through `Currency`, at the start and end of every box | swap |
| 46 | `Loot.room` weighs the room first; `EO::Carry.observe` writes a `libeo_carry` profile | feature |
| 47 | Skinning is skipped when the tool is not in hand (was bare-handed) | rule |
| 48 | Kneeling to skin gives up after 3 tries; standing after 5 | rule |
| 49 | 604 before skinning is cast three times at most (was until it showed as up) | rule |
| 50 | The learned-unskinnable list is saved once and de-duplicated | rule |
| 51 | The heirloom name is matched literally; an empty item matches nothing (was everything) | fix |
| 52 | The loot policy is rebuilt from the settings on every call | unclear |
| 53 | Removed: `Loot.occassional_skinner`, `Hoard.locker_way_in`, `booth_room?`, `approach_step`, `take_step`, `lines_since`, two constants | removed |

### Sell and the command line

| # | Change | Kind |
|---|---|---|
| 54 | A `pay` that times out counts as "can't afford": a bank trip, then "Still couldn't afford" | rule |
| 55 | Pool return with no box arriving: no count, no crash | fix |
| 56 | Pool give stops after "full" or "already open": no stray confirm | fix |
| 57 | `sell_item` reads a note only if the item left the hand | rule |
| 58 | `sell_item` no longer raises with no breakdown data | fix |
| 59 | `look on #table` at the locksmith is hidden | message |
| 60 | Three locksmith table errors collapsed into one | message |
| 61 | `;eloot settings <key> ...` is matched before `pool` and `debug`: a setting or value with those words is saved, not run as a pool trip or a debug toggle | fix |
| 62 | Selling a bundle of skins stops when a skin is left in hand, or after three unanswered BUNDLE REMOVE commands (upstream repeated without end) | rule |
| 63 | A wear refused with "You can't wear that" returns `:cant` and the script goes on (upstream exited) | rule |
| 64 | With no skinning weapon listed and an empty right hand, eloot says so; it said it was using the right hand and skinned nothing | fix |
| 65 | A LOCKER INFO that got no answer is asked again (upstream kept the nothing for the run) | fix |
| 66 | Taking an item into "a hand" picks the right hand when it is free and usable, else the left; upstream picked the right whenever it was empty, so a crippled right arm made the drag fail after a five second wait | fix |

The command-line dispatch is the same text apart from row 61, which moves one
branch ahead of two others. About 2,100 of the 2,250 lines in Sell are
untouched.

## ebounty

ebounty still launches every script upstream did (bigshot, eherbs, eloot,
echild, escortgo2). Only reading eloot's settings and the bank transaction are
now done in-process.

| # | Change | Kind |
|---|---|---|
| 1 | Lich minimum 5.19.0 -> 5.22.0 | rule |
| 2 | `;ebounty settings` "recognized names" lists the profile's keys | message |
| 3 | Typo "configurtion" fixed | message |
| 4 | Unmapped-room message reworded | message |
| 5 | `EO.room_id`: anchored, stripped; the unknown-uid text changed. An unknown boundary room ends the heirloom search with a guild error the script reports | rule |
| 6 | Containers ask the feed first; a locked one is never tried | swap |
| 7 | Deposit through `keep_silver`: `deposit all` then `withdraw <keep> silver`; upstream sent a misspelt `withdrawl` | swap + fix |
| 8 | eloot's settings are read from its profile, before eloot has run | fix |
| 9 | Fog through `Fog.return`: 8 s room-change wait (was 0.5), 1020 waits 60 s, the Sunfist and Voln gates differ | swap |
| 10 | Script-list settings: empty entries skipped (upstream ran `Script.run("")`) | fix |
| 11 | A task type that is refused echoes the reason | message |
| 12 | Empty exclusion entries ignored (upstream matched everything) | fix |
| 13 | "Who are you trying to ask" asks again in the same round, three times at most; upstream meant to and one ask was lost | fix |
| 14 | Retries of removal and expedite ask twice (was once) | rule |
| 15 | Only `EO::Guild::Error` is retried; anything else ends the script | rule |
| 16 | Guild messages and colours; the give-up text; Seldit's three lines became one | message |
| 17 | An unknown town on an assignment stops cleanly | fix |
| 18 | The 5-second wait for a guard to show now happens; upstream's loop never ran | fix |
| 19 | The heirloom name at the guard: "some" stripped, literal, case-insensitive, read fresh | fix |
| 20 | Skins in a bundle and loose ones are counted together | rule |
| 21 | Skin pre-check: not measured while hidden, MEASURE silent, case-insensitive | rule + message |
| 22 | Gem pre-check case-insensitive | rule |
| 23 | Stance before forage and search is `Stance.change` | swap |
| 24 | Kneeling to forage gives up after 3 tries and forages anyway | rule |
| 25 | Kneeling for the heirloom search gives up after 5 tries | rule |
| 26 | The forage item falls back to the herb name (upstream sent "forage for ") | fix |
| 27 | Near-herbalist turn-in gives by NPC id, with a settle | rule |
| 28 | The hurt check calls `Injured.able_to_search?` first: `_injury` commands after each forage | swap |
| 29 | "N of Q foraged" colour; the herb name regex-escaped | message + rule |
| 30 | The heirloom search searches rooms that have loot (upstream skipped them) | fix |
| 31 | 213 is stopped by the heirloom options, not the forage options | fix |
| 32 | `flag righthand off` is sent before the walk to town | rule |
| 33 | Shared helper spells: a forage `use_402` or heirloom `use_604` would now cast | rule |
| 34 | Garrote recovery and the Bard song stop on the "child already here" path | feature |
| 35 | Location names regex-escaped; the boundary list de-duplicated | rule |
| 36 | Removed from `EBounty`, `Task` and `EBounty.data`: about 40 methods and readers | removed |
| 37 | A guard's rescue and lost-heirloom replies are answers; a guard who does not answer sends the visit to the next guard (upstream raised on nil, and its pattern matched neither reply, so each ask waited out its timeout) | fix |
| 38 | The setup window's hint for the escort script says escortgo2, the default (upstream's window said ego) | message |

## ewaggle

The setup window, command line, target handling and cast passes are unchanged.

| # | Change | Kind |
|---|---|---|
| 1 | Lich minimum 5.9.0 -> 5.22.0 | rule |
| 2 | Hindered casts give up after 3 tries, with the mana made again before each; only `cast_stackable` looks for `:hindered` | rule |
| 3 | Mana bread no longer passes `valid_spell?` | rule |
| 4 | Sonic spells on self with a nil setting fall through to a plain cast | rule |
| 5 | Wracking with someone watching: waits for mana (upstream spun) | fix |
| 6 | Wracking after a walk that found nowhere to cast unseen: not cast (upstream cast it in the last room) | fix |
| 7 | `safe_to_wrack` no longer crashes in an empty room | fix |
| 8 | The walk back after wander-to-wrack uses `EO.go2` | rule |
| 9 | The wander step tolerates dead ends and unmapped rooms | fix |
| 10 | "Waiting" messages: form changed; printed after the bail check | message |
| 11 | The Symbol of Mana result match is nil-safe | fix |
| 12 | `reserve_mana` coerced with `to_i` | rule |
| 13 | The armor-buff stamina check answers ready for any zero-mana spell (no effect today) | unclear |
| 14 | Removed: `word_wrap`, `check_mana_col`, `check_mana_gos`, `check_mana_voln`, `col_move`, `safe_to_wrack` | removed |
| 15 | Debug line dropped from SPELL ACTIVE parsing | message |
| 16 | A character the game does not answer SPELL ACTIVE for in time is skipped with a message (upstream cast every spell at them, as if they had none) | fix |

## eherbs

The herb table is identical: all 247 entries match upstream by mechanical diff.

| # | Change | Kind |
|---|---|---|
| 1 | Settings in `eherbs.yaml`, copied once from CharSettings | rule |
| 2 | `UserVars.herbsack` is no longer read once the profile has a value; it is still written | rule |
| 3 | A setup save no longer wipes cached prices | fix |
| 4 | The friendly message for an old Lich is removed | removed |
| 5 | Debug output removed: `debug_msg` is defined and never called | removed |
| 6 | `;eherbs test` removed | removed |
| 7 | Empty herbsack setting: an error and exit (upstream picked the first inventory item) | fix |
| 8 | Herbsack lookup case-insensitive and escaped | rule |
| 9 | Removed data keys and code: `EHerbs::Inventory`, `Utility.get_lines`, `Actions.f2p_*` and more | removed |
| 10 | The herbalist arrival check when buying during healing; buying waits out another script's walk | feature |
| 11 | Roundtime re-send without the 0.2 s pauses | rule |
| 12 | "Won't fit" raises everywhere a put happens; at cleanup the herb is stowed and the run finishes; uncaught from `check` | rule |
| 13 | The previous herb is put back before the sack is searched; fallback `stow #id` | rule |
| 14 | "Eaten enough" raises; message reworded; uncaught from `check` | message + rule |
| 15 | Kit detection per sack (upstream read a backpack as a kit) | fix |
| 16 | `;eherbs #id` for a room object uses the id | fix |
| 17 | Kit contents refresh the dose counts on every read | rule |
| 18 | The distiller needs the detected Liquid Extractor | rule |
| 19 | Stock targets no longer compound on reload | fix |
| 20 | Dose monitor, the bundle line: counts no longer written to a nil key | fix |
| 21 | `check_silver` through `Currency` | swap |
| 22 | Free-to-play detection through `Account.type` | swap |
| 23 | Deposit: `deposit all`, 3 s, warnings; free-to-play with no access is silent | swap |
| 24 | Withdraw: needs an explicit handover line; a debt is waited through | swap |
| 25 | Pinefar: no walk to Icemule when the banker is absent | removed |
| 26 | Note withdrawal: any refusal exits (upstream crashed on one) | fix + swap |
| 27 | Note deposit: `deposit #id` | swap |
| 28 | Free-to-play withdrawal: no 5-note cap (see Known and open for where notes go) | swap |
| 29 | The silver tally is refreshed after every buy and withdraw | rule |
| 30 | The cutthroat check before reading the menu is dropped | rule |
| 31 | One fewer ORDER when prices are read | rule |
| 32 | The not-enough-silver retry is capped at one | rule |
| 33 | Clearing full hands on ORDER only for a hand that holds something | fix |
| 34 | `bundle_all` really skips "can't bundle" names, calamia fruit included | fix |
| 35 | Error messages reworded (menu miss, no price, no herb for a category) | message |
| 36 | Cost rounding can differ by 1 silver | unclear |
| 37 | `check` with nothing found says so (upstream printed an empty table) | fix |
| 38 | Blood-only with no blood herb stops (upstream warned without end) | fix |
| 39 | `--spellcast` / `--ranged`: a severed left arm picks "severed limb" (upstream listed rightHand twice) | fix |
| 40 | An escort's limb wounds are read only from a line that names a leg, arm or hand (upstream's pattern matched any line with "arm" or "hand" in it) | fix |
| 41 | Deader on a living character prints "Healdown finished" and restores the hands | rule + message |
| 42 | Deader and escort in-hand match by substring; free-hand messages reworded | message |
| 43 | Healing a dead player ends on an unanswered pour or after 20 passes, saying so; bundling potions pours at most ten times and asks with a timeout (upstream repeated without end) | rule |

## ecleanse

The control flow of every action, the saved disarm list, the hooks and the setup
window are intact. The walks force go2, as upstream's did.

| # | Change | Kind |
|---|---|---|
| 1 | Removed: `Ecleanse::Util.*`, most of `Action.*`, `CappedCollection`, Data readers | removed |
| 2 | Cached Data is reloaded on `respond_to?(:policy)` | rule |
| 3 | Help row text "Setup window" | message |
| 4 | The stun, web, settle and 213/1011 choices are read once into a `Policy` | rule |
| 5 | Detection through `Combat::Messages`: four patterns lost their end anchor, webbing is stricter, every matching row emits, supplements can add rows | swap |
| 6 | Hook errors are caught (upstream lost detection for the rest of the run) | fix |
| 7 | The Wall of Thorns poison test needs the status flag and an unexpired debuff | rule |
| 8 | The conditions table is a list: two afflictions at once are both seen to | fix |
| 9 | Cure and dispel spells are looked up live, not once at load | rule |
| 10 | Sigil of Determination is cast from inside the cast check: no pause, cast even at rank 3 | rule |
| 11 | Cleave and Thieve through `CMan.available?` and `CMan.use`: tries at 8-9 stamina, refuses on cooldown | swap |
| 12 | Acidic mist with the breeze unaffordable: does nothing (upstream cast the dispel at it) | fix |
| 13 | Berserk out of a web honours `use_berserk_webbed` | fix |
| 14 | Stun: mana pulses only for the candidates reached | rule |
| 15 | Magical debuffs with the dispel unaffordable: nothing happens | rule |
| 16 | Retreat from a root: 5 stand tries; targets again only if there was a target | rule + fix |
| 17 | The 709 check goes by the creature's noun | fix |
| 18 | Wizard's Shield only when known | fix |
| 19 | 9811 cast only if affordable | rule |
| 20 | A bonded weapon back in hand: no `fill_hands` | fix |
| 21 | Kneeling to search for a lost weapon gives up after 5 tries and searches anyway | rule |
| 22 | A webbed weapon pried free: also waits roundtime and runs `ReadyList.check` | rule |
| 23 | Telekinetic recovery capped at 10 tries | rule |
| 24 | Sanctum clench: waits for the specific line, 10 tries | rule |
| 25 | Vat room not on the map: a message, no pause (upstream ran go2 with no target) | fix |
| 26 | Hive SEARCH answers `:exhausted` straight after the third try | rule |
| 27 | Quiet commands are not sent again on "Roundtime" | rule |
| 28 | The servant's recovery stops the songs cast for the disarm (upstream left 1011 up, and 213 unless SENSE showed peace) | fix |

## escortgo2

Every route of upstream's table is present with the same commands.

| # | Change | Kind |
|---|---|---|
| 1 | go2's globals and the Vaalor shortcut timing are restored at the end | fix |
| 2 | Platinum portal-edge deletion dropped (see Known and open) | removed |
| 3 | The ambush watch is a DownstreamHook; `$ego2_my_ambush`, `$ego2_staggered_ambush` and the `$ego2_debug` echoes are gone; the cry test is looser | swap + removed |
| 4 | Target learning gives up on no answer | rule |
| 5 | The "follow" answer is no longer tied to the NPC's noun | rule |
| 6 | Route `1216,1217`: one search per try (was two); haste first | rule |
| 7 | Route `1219,1220`: search timeout 5 s (was 3); one extra room check | rule |
| 8 | Route `1242,1241`: the leading room check is gone | rule |
| 9 | Routes `902,901`, `1236,1237`, `1239,1238`: added `waitrt?` | rule |
| 10 | 29 sneak edges: one more room check before hiding | rule |
| 11 | Routes `2547,*`: stand before the second check | rule |
| 12 | Route `1042,1041` (the misty trail): LOOK TRAIL up to three times, and not gone down when none shows the way (upstream went down and moved nowhere) | fix |
| 13 | Settings in `escortgo2.yaml`; the targetable lists written on exit | rule |
| 14 | Unhide and cleanup also run on kill or error | rule |
| 15 | Messages reworded; the nine-line eherbs alert is one line | message |

## echild

| # | Change | Kind |
|---|---|---|
| 1 | Settings in `echild.yaml` | rule |
| 2 | `;echild nodisable` sticks; a stored `false` migrates and starts with disablers off | fix |
| 3 | 706's creature exclusions removed | rule |
| 4 | Start-up disabler probe: no `justice status`, no town or target filter at the start | rule |
| 5 | JUSTICE STATUS is waited for five seconds, and no answer counts as justice (upstream waited without end) | rule |
| 6 | A custom disabler is used though the character knows no disabler of the table (upstream gave up first) | fix |
| 7 | Task failed: walks back with `EO.go2`, after the current step finishes | rule |
| 8 | Standing up outside the Maaghara Labyrinth gives up after 5 tries | rule |
| 9 | `stop 1011` on exit moved to an `ensure` (may not complete on kill) | unclear |
| 10 | Finding the child: the wait message is gone; `--test:<noun>` is a regex; `$child_last_seen` is set later | rule + message |
| 11 | The reportee match is case-insensitive | rule |
| 12 | A bad room argument falls back to the nearest dropoff | fix |
| 13 | Messages; the hook renamed `_justice`; ties on mana cost by `min_by` | message |
| 14 | A number inside an option (`--disabler=617`, `--test:owl2`) is not taken as the destination room | fix |
| 15 | TARGET RANDOM waits five seconds for its answer, and learns only the hostile names the game refuses; upstream waited without end and learned every NPC in the room, the child included, and saved them | fix |

## ewander

| # | Change | Kind |
|---|---|---|
| 1 | Settings in `ewander.yaml` | rule |
| 2 | The eloot wait runs before every step, the Confluence included | rule |
| 3 | A delay after any TARGET RANDOM that targets nothing | rule |
| 4 | Outside GSIV the Confluence no longer leaves status tags on | fix |
| 5 | GSIV Confluence: learned exits are wiped even if the room changed mid-check | rule |
| 6 | GSIV Confluence: a step starts over ten times at most (upstream retried without end) | rule |
| 7 | Either Confluence step does not move when LOOK is not answered or shows no exits | fix |
| 8 | Unknown current room: sleeps the delay | fix |
| 9 | `target_random!` takes its room snapshot later | rule |
| 10 | An exit whose scripted travel time is nil (closed by the map) is not stepped to; upstream's `is_a?(Proc)` did not match a StringProc, so it could step into one | fix |
