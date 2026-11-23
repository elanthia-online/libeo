# frozen_string_literal: true

module EO
  module Loot
    # Looting what lies in a room and in the boxes and bags found there: the
    # items that need handling one by one (coins, cursed things, orbs, keepers),
    # then the ordinary ones, by the game's LOOT ROOM where it can and by hand
    # where it cannot. Each item goes through the caller's drag, so what to do
    # when every bag is full stays the caller's.
    class Floor
      # Items in the highlands that LOOT ROOM does not take.
      UNCOMMON = ['stygian valravn quill', 'nacreous disir feather', 'silver-veined black draconic idol'].freeze

      # What LOOT takes into its bag, as against dragging it there.
      LOOT_CMD_ITEMS = /clothing|jewelry|gem|herb|skin|wand|scroll|potion|reagent|trinket|lockpick|treasure|forageable|magic|collectible|lockandkey/

      # @param context [EO::Loot::Context, #settings] the settings, the stow, the
      #   patterns, the charm; where to say something and to save
      # @param hands [#free_hand, #free_hands, #single_drag, #single_loot, #drag, #open_loot_containers]
      #   what frees a hand, puts an item away (:full when told to signal and
      #   nothing has room), takes it with LOOT, drags it into a hand, and
      #   opens the bags loot is about to go into (eloot's Inventory)
      # @param command [Proc] given a command, the pattern of its answer and
      #   silent: and quiet:, the answer's lines (eloot's get_command)
      # @param result [Proc] given a command and a pattern, the answer's line
      #   (eloot's get_res)
      # @param decurse [Proc] given an item, whether it may be picked up now
      # @param unlootable [Proc] given an item the game would not loot
      # @param toss [Proc] given an item, a command and attempts:, whether it
      #   left the hand
      # @param stow_box_item [Proc, nil] given an item of a box, the box, its
      #   location, its ledger and whether a recovery ran, puts it away and
      #   says :recovered when a recovery looted the whole box; without one the
      #   item is put away, and dragged by hand when nothing has room
      # @param snapshot [Proc, nil] returns the inventory feed's snapshot for a
      #   pass, nil when there is none to take
      def initialize(context, hands:, command:, result:, decurse:, unlootable:, toss:, stow_box_item: nil, snapshot: nil)
        @context = context
        @hands = hands
        @command = command
        @result = result
        @decurse = decurse
        @unlootable = unlootable
        @toss = toss
        @stow_box_item = stow_box_item
        @snapshot = snapshot || -> { Lich::Common::Inventory.refresh }
      end

      # --- what is loot --------------------------------------------------------

      # The settings as libeo's loot policy; rebuilt each call so a changed
      # profile is honoured.
      #
      # @return [EO::Loot::Policy]
      def policy
        Policy.from_settings(settings, level: Stats.level, heirloom: Bounty.task.heirloom? ? Bounty.task.requirements[:item] : nil)
      end

      # @return [Array<GameObj>] the room objects that are loot
      def reject_invalid_loot(objs) = Loot.loot(objs, policy)

      def should_grab_item?(thing) = Loot.wanted?(thing, policy)

      # @return [Array<GameObj>] the objects the character wants
      def valid_objs(objs) = objs.select { |o| should_grab_item?(o) }

      # @return [Array<GameObj>] the objects it does not
      def invalid_objs(objs) = objs.reject { |o| should_grab_item?(o) }

      # --- the room ------------------------------------------------------------

      # Loot the room. The bags' weights are this pass's: they are forgotten
      # when it ends, as selling or hoarding empties bags after it.
      #
      # @return [void]
      def room
        objs = room_candidates

        objs = loot_specials(objs) unless objs.empty?

        # Anything left after boxes, collectibles, and uncommon weapon/armor?
        loot_regular(objs, 'Room') unless objs.empty?
      ensure
        forget_weights
      end

      # What the room holds that is loot, weighed for this pass.
      #
      # @return [Array<GameObj>]
      def room_candidates
        objs = reject_invalid_loot(GameObj.loot.to_a)
        weigh_room unless objs.empty?
        objs
      end

      # Forget the weights taken for a pass.
      #
      # @return [void]
      def forget_weights = stow.observe(nil)

      # Open the bags loot is about to go into.
      #
      # @param objs [Array<GameObj>] what is to be looted
      # @return [void]
      def open_bags(objs) = @hands.open_loot_containers(objs)

      # One inventory snapshot for the pass: every item's weight, the floor's
      # too, and the room in each bag, so a bag too full for an item is passed
      # over without trying; the encumbrance it shows teaches EO::Carry.
      #
      # @return [void]
      def weigh_room
        stow.observe(nil)
        snapshot = @snapshot.call
        return unless snapshot

        stow.observe(snapshot)
        Carry.observe(snapshot)
      rescue StandardError => e
        say('debug', "weigh_room: #{e.message}")
      end

      # Loot a bag dropped from a critter that has treasure in it.
      #
      # @param bag [GameObj]
      # @return [String, false, nil] "crumbly" when it decayed on opening, false
      #   when the game could not find it, nil otherwise
      def bag_loot(bag)
        return if @context.checked_bags.include?(bag.id)

        lines = @command.call("open ##{bag.id}", /crumbles? and decays? away|<exposeContainer|That is already open|<container|There doesn't seem to be any way to do that|I could not find what you were referring to/, silent: true, quiet: true)

        if lines.any? { |l| l =~ /crumbles? and decays? away/i }
          unless bag.name =~ /bandana|flowing robes/
            say('info', " #{bag} was crumbly, adding to list")
            settings[:crumbly].push(bag.name)
            @context.save
          end
          return 'crumbly'
        end

        if lines.any? { |line| line =~ /There doesn't seem to be any way to do that|I could not find what you were referring to/i }
          @context.checked_bags.push(bag.id)
          return
        end

        lines = @command.call("look in ##{bag.id}", /<container|That is closed/, silent: true, quiet: true)

        # False positive?
        return false if lines.any? { |line| line =~ /I could not find what you were referring to/i }

        objs = reject_invalid_loot(bag.contents)

        if objs.empty?
          @context.checked_bags.push(bag.id)
          return
        end

        objs = loot_specials(objs)

        # Anything left after boxes, collectibles, and uncommon weapon/armor?
        if objs.empty?
          @context.checked_bags.push(bag.id)
          return
        end

        loot_regular(objs)

        @context.checked_bags.push(bag.id)
      end

      # Loot every box lying in the room, whole: open it, take its coins and
      # what is in it, then keep the box or throw it away.
      #
      # @return [Symbol, nil] :coins_full when the character cannot hold any
      #   more coins, which the caller ends on
      def box_loot_ground
        @hands.free_hands(both: true)

        box_list = GameObj.loot.find_all { |x| x.type == 'box' }

        box_list.each do |box|
          opened = Boxes.open(box, quiet: !settings[:display_box_contents])
          next if opened == :locked
          if opened == :unknown
            say('info', " Unable to determine the contents of  #{box.name}.")
            next
          end

          # Drag the box to our hand
          @hands.drag(box)

          # Get the coins
          case Boxes.coins(box, charm: @context.charm).first
          when :full
            say('info', " Can't hold any more coins...Exiting!")
            return :coins_full
          when :unknown
            say('info', ' Unknown get coin result, leaving the coins.')
          end

          # Loot the rest of the stuff
          objs = box.contents
          unless objs.empty?
            specials = loot_specials(objs, box: box)
            # A recovery already re-looted and finalized this box via a nested box_loot;
            # skip the cleanup below rather than run it against a gone box.
            next if specials == :recovered

            objs = specials
          end

          unless objs.empty?
            next if loot_regular(objs, 'Box', box) == :recovered
          end

          save_box = settings[:sell_loot_types].include?('box')
          valuable_box = Boxes::VALUABLE

          # If it's a save box and empty, just store it immediately also don't toss Reliquaries
          if Boxes.keep?(box, sell: save_box)
            @hands.single_drag(box, false)
            next
          end

          trash = Town.trash_can

          toss_cmd = trash.nil? ? 'drop' : 'trash'

          if save_box && box.name =~ valuable_box && !box.contents.any? { |obj| obj.type =~ /cursed/ }
            box.contents.each do |item|
              @hands.drag(item)

              # if it didn't toss, it might be special (or marked) - save it
              @hands.single_drag(item) unless @toss.call(item, toss_cmd)
            end
          else
            @toss.call(box, toss_cmd, attempts: 4)
          end

          @hands.single_drag(box, false) if Hands.holding?(box)
        end
        nil
      end

      # Loot the entire room with the game's LOOT ROOM.
      #
      # @param items [Array<GameObj>] the loot the room holds
      # @return [true, nil] true when the game said there is nothing it will take
      def loot_all(items)
        waitrt?

        @hands.free_hand

        res = @command.call('loot room', /<dialogData|There is no loot|You need a free hand to do that|With a discerning eye|You note some treasure of interest|You can't.*?It's closed!/)

        if res.any? { |l| l =~ /There is no loot/ }
          items.each { |item| @unlootable.call(item) }
          return true
        end

        learn_closed_bags(items) if res.any? { |l| l =~ /You can't.*?It's closed!/ }

        # Didn't get it all?...something in-hand?
        return unless res.any? { |l| l =~ /(?:gather|pick) up and stow (?:what|as much) treasure .+ manage|but quickly realize|before realizing you have no room/ }

        [GameObj.right_hand, GameObj.left_hand].each do |hand|
          @hands.single_drag(hand) if items.any? { |thing| thing.id == hand.id }
        end

        # Anything left?
        objs = reject_invalid_loot(GameObj.loot.to_a)
        return if objs.empty?

        # Still here so rerun the room
        room
        nil
      end

      # Loot the ordinary items. In a box-looting flow a full-container stow can trigger the
      # locksmith pool sell-and-resume recovery, which re-loots AND finalizes the whole box.
      #
      # @param objs [Array<GameObj>]
      # @param from_where [String, nil] "Room", "Box" or nil for a bag
      # @param box [GameObj, nil] the box being looted
      # @return [Symbol, nil] :recovered when that happened -- the caller must stop and must
      #   not finalize the box again; nil otherwise.
      def loot_regular(objs, from_where = nil, box = nil, sell_recovered: false, location: nil, data: nil)
        say('debug', "objs: #{objs} | from_where: #{from_where} | sell_recovered: #{sell_recovered} | location: #{location.inspect} | data?: #{!data.nil?}")

        if from_where == 'Room'
          room_regular_steps(objs).each(&:call)
          return nil
        end

        valid = valid_objs(objs.clone)
        invalid = invalid_objs(objs.clone)

        say('debug', "valid: #{valid}")
        say('debug', "invalid: #{invalid}")

        if !invalid.empty? && !valid.empty?
          @hands.free_hand
          if from_where == 'Box'
            return :recovered if valid.any? { |thing| stow_box_item(thing, box, location, data, sell_recovered) == :recovered }
          else
            valid.each { |thing| @hands.single_drag(thing) }
          end
        elsif invalid.empty? && !valid.empty?
          # Make sure we have a hand free
          @hands.free_hand
          say('debug', 'invalid.empty? && !valid.empty?')

          if from_where == 'Box'
            return :recovered if loot_box(box, location, data, sell_recovered) == :recovered
          else
            valid.each { |thing| @hands.single_drag(thing) }
          end
        end

        report_left(invalid)
        nil
      end

      # Loot the items that need individual handling (coins, cursed items, orbs,
      # uncommon weapons/armor, keepers) and return whatever is left for loot_regular.
      #
      # When called from a box-looting flow the caller passes the box context. That makes a
      # full-container stow eligible for the same locksmith pool sell-and-resume recovery
      # loot_regular already uses, instead of pausing the script. Without the context (room
      # looting, critter bags) the behavior is unchanged: stow, and pause if nothing fits.
      #
      # @param objs [Array<GameObj>] candidate items
      # @param box [GameObj, nil] the box being looted; nil outside a box-looting flow
      # @param location [String, nil] passed through to the recovery
      # @param data [Hash, nil] passed through to the recovery
      # @param sell_recovered [Boolean] true when a recovery already ran for this box.
      # @return [Array<GameObj>, Symbol] items left for loot_regular, or :recovered when a
      #   recovery re-looted AND finalized the whole box. Only reachable when box is given.
      def loot_specials(objs, box: nil, location: nil, data: nil, sell_recovered: false)
        say('debug', "objs: #{objs} | box: #{box.respond_to?(:name) ? box.name : box.inspect} | sell_recovered: #{sell_recovered}")

        # Open sacks for looting the room
        @hands.open_loot_containers(objs)

        recovered = false

        objs = objs.reject do |thing|
          # A recovery re-looted the whole box already; stop touching the stale list.
          next false if recovered

          outcome = special(thing, box: box, location: location, data: data, sell_recovered: sell_recovered)
          recovered = true if outcome == :recovered
          outcome
        end

        if recovered
          say('debug', 'loot_specials: pool recovery re-looted and finalized the box')
          return :recovered
        end

        say('debug', "After specials check objs: #{objs}")

        objs
      end

      # One item for loot_specials: a clothing bag looted first, then the item
      # taken if it is one that needs handling of its own.
      #
      # @param thing [GameObj]
      # @return [Boolean, Symbol] true when the item is dealt with (taken, or a
      #   bag that decayed) and no longer left for loot_regular, false when it
      #   is left, :recovered when a recovery looted the whole box
      def special(thing, box: nil, location: nil, data: nil, sell_recovered: false)
        result = bag_loot(thing) if thing.type =~ /clothing/

        return true if result == 'crumbly'
        return false if thing.name.match?(@context.loot_exclude_regex)
        return false if thing.name.eql?('shard of oblivion quartz') && Stats.level.eql?(100) && settings[:loot_types].include?('gem')
        return false if thing.type =~ /cursed/ && !settings[:loot_types].include?('cursed')
        return false unless special?(thing)

        outcome = true
        if thing.name =~ /silver coin/
          coin_cmd = @context.charm.nil? ? 'get coins' : "rub ##{@context.charm.id}"
          @result.call(coin_cmd, /you (gather|summon)/i)
        elsif @decurse.call(thing)
          @hands.free_hand
          if box
            outcome = :recovered if stow_box_item(thing, box, location, data, sell_recovered) == :recovered
          else
            @hands.single_drag(thing)
          end
        end
        outcome
      end

      # What looting the ordinary items of a room comes to, one action at a
      # time: LOOT ROOM for all of them when every one is wanted, else each
      # wanted item by LOOT or by hand. The last action says what was left.
      #
      # @param objs [Array<GameObj>]
      # @return [Array<Proc>] actions to call in order
      def room_regular_steps(objs)
        valid = valid_objs(objs.clone)
        invalid = invalid_objs(objs.clone)

        unless settings[:loot_types].include?('coins')
          valid.reject! { |o| o.name =~ /silver coin/ }
          invalid.concat(GameObj.loot.select { |o| o.name =~ /silver coin/ })
        end

        say('debug', "valid: #{valid}")
        say('debug', "invalid: #{invalid}")

        steps = []
        if !invalid.empty? && !valid.empty?
          valid.each_with_index do |obj, index|
            steps << lambda do
              @hands.free_hand if index.zero?
              obj.type =~ LOOT_CMD_ITEMS ? @hands.single_loot(obj) : @hands.single_drag(obj)
            end
          end
        elsif invalid.empty? && !valid.empty?
          steps << lambda do
            # Make sure we have a hand free
            @hands.free_hand
            say('debug', 'invalid.empty? && !valid.empty?')
            loot_all(valid)
          end
        end

        report = -> { report_left(invalid) }
        last = steps.pop
        steps << (last ? -> { last.call; report.call } : report)
        steps
      end

      private

      # Say what a pass left behind.
      def report_left(invalid)
        left_behind = invalid.map(&:name)
        say('info', " Left the following item#{left_behind.length > 1 ? 's' : ''}: #{left_behind.join(', ')}.") unless left_behind.empty?

        say('debug', 'End of method')
      end

      # Whether an item is one of those that need handling of their own.
      def special?(thing)
        loot_uncommon_regex = Regexp.union(UNCOMMON)
        (thing.type.to_s.split(',').any? { |t| @context.allowed_special_types.include?(t.strip) }) ||
          (thing.type =~ /lockandkey/i) ||
          thing.name.match?(@context.loot_keep_regex) ||
          (thing.type =~ /cursed/i && settings[:loot_types].include?('cursed')) ||
          (thing.type =~ /weapon/i && thing.type =~ /uncommon/ && settings[:loot_types].include?('weapon')) ||
          (thing.type =~ /armor/i && thing.type =~ /uncommon/ && settings[:loot_types].include?('armor')) ||
          (thing.name =~ /orb/ && thing.type =~ /magic/ && settings[:loot_types].include?('magic')) ||
          (thing.name =~ loot_uncommon_regex && settings[:loot_types].include?('uncommon')) ||
          (thing.name =~ /silver coin/ && settings[:loot_types].include?('coins'))
      end

      def settings = @context.settings

      def stow = @context.stow

      def say(type, text) = @context.say(type: type, text: text)

      # Put an item of a box away: through the caller's, which may recover a
      # full pack by selling, else the item is put away and dragged by hand
      # when nothing has room.
      def stow_box_item(thing, box, location, data, sell_recovered)
        return @stow_box_item.call(thing, box, location, data, sell_recovered) if @stow_box_item

        @hands.single_drag(thing) if @hands.single_drag(thing, on_full: :signal) == :full
        nil
      end

      # LOOT a box's contents into the bags, then see what is left in hand and
      # in the box.
      #
      # @return [Symbol, nil] :recovered
      def loot_box(box, location, data, sell_recovered)
        @command.call("loot ##{box.id}", /You search through|You can't.*?It's closed!|There is no loot|In an attempt/i, silent: false, quiet: false)
        EO.settle

        # If bag fills up it can leave an item in hand
        recovered = [GameObj.right_hand, GameObj.left_hand].any? do |item|
          next false if item.type == 'box'

          stow_box_item(item, box, location, data, sell_recovered) == :recovered
        end
        return :recovered if recovered

        # if there are still box contents the default container has filled up so just do the rest as drags
        if box.contents.length.positive?
          remaining_valid = valid_objs(box.contents.clone)

          return :recovered if remaining_valid.any? { |thing| stow_box_item(thing, box, location, data, sell_recovered) == :recovered }
        end
        nil
      end

      # A bag that closed itself, found by LOOT ROOM saying a bag was closed.
      def learn_closed_bags(items)
        items_opened = []
        items.each do |item|
          item_type = item.type.to_sym
          bag = if StowList.stow_list[item_type] && !stow.full?(StowList.stow_list[item_type])
                  StowList.stow_list[item_type]
                else
                  StowList.stow_list[:default]
                end

          next if items_opened.include?(bag.name)

          items_opened.push(bag.name)

          next unless stow.closes_itself?(bag)

          # check if open
          lines = @command.call("look in ##{bag.id}", @context.look_regex, silent: true, quiet: true)
          stow.learn(:auto_close, bag) if lines.any? { |l| l =~ /That is closed./ }
        end
      end
    end
  end
end
