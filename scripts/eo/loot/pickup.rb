# frozen_string_literal: true

module EO
  module Loot
    # Picking up one item for a looting pass: putting what is in hand where
    # the STOW list says, a box in a disk first when disks are used, and
    # LOOT's own way of taking an item into its bag.
    #
    # What to do when nowhere has room is the caller's: #drag says
    # :no_room and goes no further, so eloot can pause for the player and
    # eohunter can rest.
    class Pickup
      # @param context [EO::Loot::Context, #settings] the settings, the stow,
      #   the disks and the put pattern, where to say something
      # @param hands [#store_item, #open_single_container, #single_drag]
      #   what puts an item in a bag, opens one, and drags an item the whole
      #   way (eloot's Inventory)
      # @param command [Proc] given a command and the pattern of its answer,
      #   returns the answer's lines (eloot's get_command)
      # @param inventory [Proc] returns what the sell containers and the disk
      #   hold (eloot's Sell.check_inventory)
      # @param wait_for_disk [Proc] waits for the character's disk to arrive
      def initialize(context, hands:, command:, inventory:, wait_for_disk:)
        @context = context
        @hands = hands
        @command = command
        @inventory = inventory
        @wait_for_disk = wait_for_disk
      end

      # Put an item where the STOW list says: a box in a disk first, then the
      # bags along its route. When none takes it, a box is moved aside to make
      # room, once, and the route is tried again; a bag known to lack the room
      # is not tried, so that happens before the item is picked up.
      #
      # @param item [GameObj]
      # @param phase [Boolean] phase a box once it is put away, when the
      #   settings say so
      # @param room_made [Boolean] a box was already moved aside for this item
      # @return [Symbol, nil] :stored, :no_room (nowhere took it), :no_default
      #   (no default bag is set, which the STOW list must have), or nil for
      #   an item that is "Empty"
      def drag(item, phase: true, room_made: false)
        return nil if item&.name == 'Empty'
        return :stored if drag_box(item)

        placed = store_on_route(item, phase)
        return placed if placed

        # Nowhere had the room: move a box aside to make some, once, and try again
        disk = settings[:use_disk] ? @context.disk : nil
        refused = @context.disk_full[Char.name] ? true : false
        return drag(item, phase: phase, room_made: true) if !room_made && at_hand?(item) && stow.make_room(item, disk: disk, full: refused)

        :no_room
      end

      # Put a box in a disk, so the disks carry the heaviest. A box heavier
      # than one on a disk takes its place, the lighter going to the box or
      # overflow bag. Any other is tried as one more box on a disk, the
      # character's own first and then a group member's, until the game
      # refuses it; a disk that refused is full.
      #
      # @param item [GameObj]
      # @return [Boolean] whether the box went into a disk
      def drag_box(item)
        say('debug', "item: #{item.inspect}")

        return false unless item.type == 'box'
        return false unless settings[:use_disk] || settings[:use_disk_group]

        # Only wait if the characters disk exists
        @wait_for_disk.call unless @context.disk.nil?

        # the swap moves a box off the disk, which needs a hand: only for a
        # box still on the floor
        unless Hands.holding?(item)
          return true if swap_into_disk(item)
          # the disk refused it after the swap: on to the bags
          return false if Hands.holding?(item)
        end
        return false unless disk_open?

        put = lambda do |disk, box|
          if @hands.store_item(disk, box)
            stow.placed(disk, box)
            next true
          end

          # inform user it didn't fit
          say('info', " The #{box} won't fit in the #{disk.name} disk. Trying a different disk.") if @context.disk_full.size > 1
          false
        end
        return true if Boxes.to_disk(item, full: @context.disk_full, put: put, group: settings[:use_disk_group])

        say('info', " The #{item} won't fit in any disk(s). Trying a different container.")
        false
      end

      # Whether a disk may be tried: one is not known to be full, and it is
      # the character's own unless group disks are used.
      #
      # @return [Boolean]
      def disk_open?
        return false unless @context.disk_full.value?(false)

        settings[:use_disk_group] || !(@context.disk.nil? || @context.disk_full[Char.name])
      end

      # A box heavier than one on a disk takes its place, the lighter going
      # to the box or overflow bag.
      #
      # @param item [GameObj] a box
      # @return [Boolean] whether it went onto a disk
      def swap_into_disk(item)
        disks = Boxes.disks(group: settings[:use_disk_group]).filter_map { |d| GameObj[d.id] }
        on = disks.map { |d| "#{d.name}: #{stow.box_weights(d)&.join(', ') || 'not weighed'}" }.join('; ')
        # the box is still on the floor, so the move off the disk has a hand
        disk = stow.disk_slot(item, disks)
        verdict = disk ? "swapping onto #{disk.name}" : 'no swap'
        say('debug', "disk swap: #{item.name} weighs #{stow.weight_of(item) || 'unknown'}; boxes on #{on}; #{verdict}")
        return false unless disk && @hands.store_item(disk, item)

        stow.placed(disk, item)
        true
      end

      # Take an item into its bag with LOOT, which puts it where the game's
      # own treasure system says; when that fails or the bags are full, drag
      # it the whole way.
      #
      # @param item [GameObj, nil]
      # @return [Boolean, Object, nil] true when it went in, else what the
      #   caller's drag answered
      def loot(item)
        say('debug', "item: #{item.inspect}")
        return if item.nil?

        # loot item will fallback to the default sack but if both are full we need to loot manually
        bag = StowList.stow_list[item.type.to_sym]
        bag = nil if stow.full?(bag)
        bag ||= StowList.stow_list[:default]
        bag = nil if stow.full?(bag)

        unless bag
          @hands.single_drag(item)
          return
        end

        lines = @command.call("loot ##{item.id}", @context.put_regex)

        if lines.any? { |line| line =~ %r{</inv>You can't put your <a exist=".*?" noun=".*?">.*?</a> in the <a exist="(\d+)" noun=".*?">.*?</a>.  It's closed!} }
          bag_id = Regexp.last_match(1)
          bag = GameObj.inv.find { |i| i.id == bag_id }
          if stow.closes_itself?(bag)
            stow.learn(:auto_close, bag)
            @hands.open_single_container(bag)
          end
        end

        20.times do
          return true if !Hands.holding?(item) && ids_in(StowList.stow_list[item.type.to_sym]).include?(item.id)
          return true if !Hands.holding?(item) && ids_in(StowList.stow_list[:default]).include?(item.id)
          return true if !Hands.holding?(item) && item.type =~ /skin/

          sleep 0.1
        end

        # edge case of treasure system mismatch
        return true if @inventory.call.any? { |obj| obj.id == item.id }

        # still here so just loot it manually
        @hands.single_drag(item)
      end

      private

      def settings = @context.settings

      # In a hand or still on the floor: not gone, and not put away.
      def at_hand?(item) = Hands.holding?(item) || GameObj.loot.to_a.any? { |o| o.id == item.id }

      def stow = @context.stow

      # The ids of what a bag holds; none for a bag that is not set.
      def ids_in(bag) = (bag&.contents).to_a.map(&:id)

      def say(type, text) = @context.say(type: type, text: text)

      # The bags along the item's route, in order, past the full ones.
      #
      # @return [Symbol, nil] :stored, :no_default, nil when no bag took it
      def store_on_route(item, phase)
        stow.route(item).each_with_index do |bag, index|
          if stunned?
            say('debug', 'single_drag: character stunned, waiting for it to clear')
            wait_while { stunned? }
          end
          next if stow.full?(bag)

          if bag.nil?
            case index
            when 0
              # Skip if item-specific container not set (this is normal)
            when 1
              say('yellow', " No default container identified. This shouldn't happen.")
              say('yellow', '   Check your STOW settings. Exiting')
              return :no_default
            else
              # Overflow container not identified (this is normal if not all overflow containers are set)
              say('info', " Skipping overflow container #{index - 1}. No container identified.")
            end
          elsif @hands.store_item(bag, item)
            Items.phase(item) if phase && settings[:loot_phase]
            return :stored
          end
        end
        nil
      end
    end
  end
end
