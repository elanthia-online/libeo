# Looting without running eloot

eloot's looting pass is in libeo, so a script that hunts can loot a room itself, a
step at a time, instead of starting `;eloot` and waiting for it to end. This is for
the author of such a script. eloot itself runs the same classes, so what is here is
what eloot does, and what it leaves to the caller is listed under "What the caller
decides".

None of it has run in the game yet: it is checked by specs that stand in for the
game, and by eloot's own use of it once that has been tried.

## The pieces

| Class | What it does |
|---|---|
| `EO::Loot::Context` | the settings, the stow, and what a pass keeps (hands, disk, coins, patterns); where to say something and to save |
| `EO::Loot::Handler` | free a hand, draw an item, put it away, open the bags, give the hands back; never pauses, never ends the script |
| `EO::Loot::Pickup` | one item: a box into a disk, an item into the first bag on its route, a box moved aside when none has room |
| `EO::Loot::Floor` | the room's loot: the special items one by one, the ordinary loot by LOOT ROOM or by hand, bags, boxes lying in the room |
| `EO::Skinning::Pass` | skinning, a tool group at a time |
| `EO::Loot::Pass` | one pass over a room: skin, search, loot the floor, coin hand, hands back |

A pass is built from the bottom: a Context, then a Handler over it, then the Floor
and the skinning pass with the Handler as their `hands`, then the Pass.

## Putting it together

A sketch, with the hooks left as what each must be (see below):

```ruby
settings = EO::Settings.load_profile('eloot')          # the player sets looting up once
context = EO::Loot::Context.from_settings(settings, say: say, save: save)
context.charm = ...    # what the character has: charm, gauntlet, blood_band, weapon_inv

hands = EO::Loot::Handler.new(context, command: command, inventory: inventory, wait_for_disk: wait_for_disk)
floor = EO::Loot::Floor.new(context, hands: hands, command: command, result: result, decurse: decurse,
                                     unlootable: unlootable, toss: toss)
skin = -> { EO::Skinning::Pass.new(context, corpses: GameObj.dead.to_a, hands: hands, ensure_items: ensure_items) }
pass = EO::Loot::Pass.new(context, floor: floor, hands: hands, corpses: -> { GameObj.dead.to_a }, skin: skin,
                                   stance: stance, coin_hand: -> {}, return_hands: -> { hands.return_hands })
```

Then, either `pass.run` for the whole pass, or a step at a time:

```ruby
pass.start
loop do
  case pass.step
  when :done then break
  when :no_room then ...        # pass.last is the item that is still in a hand
  end
  # the script's other behaviours take their turn here
end
pass.finish
```

`step` answers `:skinned` or `:no_tool` (a skinning group), `:searched` (a corpse),
`:special` (an item that needed handling of its own), `:looted` (the ordinary loot, or
one item of it), `:no_room`, or `:done`. Every step ends with what it handled put
away, so the hands are free between steps; the character may still be kneeling after
a skinning step until `finish`.

To leave a pass before it is done, call `pass.finish` (it stands the character up from
skinning and forgets the bag weights), then `pass.restore_hands` to give each hand back
what it held when the pass began.

## The hooks

Each is a Proc the caller supplies, because it is how the script talks to the game.
eloot's own are in `scripts/eloot.lic`, under the name given.

| Hook | What it must do | eloot's |
|---|---|---|
| `command` | send a command and answer its lines as the game marks them up (`usexml: true`); send it again if the game says it is in roundtime | `ELoot.get_command` |
| `result` | send a command and answer the one line that matches; again after roundtime | `ELoot.get_res` |
| `inventory` | what the sell containers and the disk hold | `Sell.check_inventory` |
| `wait_for_disk` | wait for the character's disk to arrive | `ELoot.wait_for_disk` |
| `decurse` | given an item, whether it may be picked up now (a cursed one is made safe, or left) | `ELoot.decurse` |
| `unlootable` | given an item the game would not loot, remember it | `ELoot.unlootable` |
| `toss` | given an item, a command and `attempts:`, whether it left the hand | `ELoot.toss` |
| `stance` | given a stance name, change to it (not in a frenzy) | `ELoot.change_stance` |
| `ensure_items` | find the listed skinning weapon or sheath again when the lists changed | `ELoot.ensure_items` |
| `say`, `save` | show a message; write the settings back after something was learned | `ELoot.msg`, `ELoot.save_profile` |

A hook the script has no use for can be a Proc that does nothing: `coin_hand` is
eloot's weightless-coin-container handling, and `ensure_items` can be left out when
Lich's READY list is trusted.

## What the caller decides

- **A full pack.** eloot pauses and tells the player. The Handler never does: its
  `single_drag` answers `:full` (nothing has room) or `:no_default` (no default bag is
  set), and the pass says `:no_room` when an item is still in a hand after a step. A
  hunting script can rest, drop the item, or stop the pass.
- **A hand that cannot be used.** eloot ends the script. The Handler's `drag` answers
  `:crippled` (neither hand is usable) or `:overloaded` (the item cannot be picked up).
- **A skinning tool put away.** eloot notes it for its room recovery
  (`on_tool_stow:` of the Handler). A script without one leaves it out.
- **The locksmith pool.** A full pack while looting a box in a locksmith's room is
  eloot's to recover from by selling (`stow_box_item:` of the Floor); without one the
  item is put away, and dragged by hand when nothing has room.

## Limits

- The inventory snapshot that tells which bags are full is taken once, when the floor
  starts. A bag that fills afterwards is found full when it is tried.
- A step is as long as its action: skinning is a step per tool group, and LOOT ROOM
  (which takes everything at once) is one step.
- A group member's floating disk is not counted here (its capacity is not known): a box goes in it
  until the game refuses it.
- `:no_room` is seen from the hands. A pass that keeps going after one will try to
  free a hand again, and be told `:full` again.
