# frozen_string_literal: true

module EO
  module Loot
    # What a looting pass does with the hands and the bags: free a hand, draw an
    # item, put it away where the STOW list says, open the bags loot goes into,
    # and give the hands back what they held. It never pauses and never ends the
    # script: where eloot stops for the player or exits, this says so in what
    # it answers (:full, :crippled, :overloaded), and the caller decides.
    #
    # It answers what libeo's looting classes ask of their +hands+: pass it as
    # the hands of an EO::Loot::Pickup, Floor, Pass or EO::Skinning::Pass.
    class Handler
      # @param context [EO::Loot::Context, #settings] the settings, the stow, the
      #   sell containers, the hands at the start of the pass
      # @param command [Proc] given a command, the pattern of its answer and
      #   silent: and quiet:, the answer's lines
      # @param inventory [Proc] returns what the sell containers and the disk hold
      # @param wait_for_disk [Proc] waits for the character's disk to arrive
      # @param stow [Proc, nil] given an item in hand, puts it away; without one
      #   it is put away with #single_drag
      # @param on_tool_stow [Proc, nil] given a skinning tool and the bag it is
      #   about to be put in, returns a record whose :settled is set once the
      #   tool has left the hand
      # @param autoclosers_due [Proc, nil] whether the bags that close themselves
      #   are to be opened again now; without one they are, every time
      def initialize(context, command:, inventory:, wait_for_disk:, stow: nil, on_tool_stow: nil, autoclosers_due: nil)
        @context = context
        @command = command
        @inventory = inventory
        @wait_for_disk = wait_for_disk
        @stow = stow
        @on_tool_stow = on_tool_stow
        @autoclosers_due = autoclosers_due
      end

      # Put away what is in a hand: a readied weapon to its sheath, else a bag.
      #
      # @param hand [GameObj, nil]
      # @return [void]
      def put_away(hand)
        return if hand.nil? || hand.id.nil?

        key = ready_key(hand)
        return if key && Hands.stow_ready(key, hand)

        (@stow || method(:single_drag)).call(hand) if Hands.holding?(hand)
      end

      # Take an item into a hand, a hand freed for it.
      #
      # @param item [GameObj, nil]
      # @param to [String] "hand", "right" or "left"
      # @return [Boolean, Symbol, nil] true when it is held, false when it
      #   could not be found, :crippled (neither hand is usable), :overloaded
      #   (it cannot be picked up), nil when there was nothing to take
      def drag(item, to = 'hand')
        say('debug', "item: #{item.inspect}")
        return if item.nil? || item.empty? || item.name == 'Empty'

        case Hands.take(item, to: to.to_sym, stow: ->(hand) { put_away(hand) }, favor_left: settings[:favor_left])
        when :held then true
        when :crippled then :crippled
        when :overloaded then :overloaded
        when :missing
          StowList.stow_list.each_value { |bag| open_single_container(bag) }
          lost = @inventory.call.find { |obj| obj.id == item.id }
          return drag(lost, to) if lost

          say('info', " Can't find #{item.name}. Looked in all the bags in case it got misplaced.")
          false
        else false
        end
      end

      # Free a hand: the right, or the left when that is the one to favour.
      #
      # @return [Symbol, nil] :crippled when neither hand is usable
      def free_hand
        Hands.free_hand(stow: ->(hand) { put_away(hand) }, favor_left: settings[:favor_left]) == :crippled ? :crippled : nil
      end

      # Put away what is in the hands asked for.
      #
      # @return [void]
      def free_hands(right: false, left: false, both: false)
        put_away(GameObj.right_hand) if (right || both) && checkright
        put_away(GameObj.left_hand) if (left || both) && checkleft
      end

      # Open a bag for looting into it, noting that it was opened.
      #
      # @param sack [GameObj, String, Symbol, nil] the bag, a stow-list key, or a bag's id
      # @return [void]
      def open_single_container(sack)
        say('debug', "sack: #{sack}")
        return if sack.nil? || sack.empty?

        container = if sack.is_a?(GameObj)
                      sack
                    elsif StowList.stow_list[sack.to_sym]
                      StowList.stow_list[sack.to_sym]
                    elsif GameObj[sack]
                      GameObj[sack]
                    end
        if container.nil?
          say('debug', "not able to determine proper GameObj lookup for #{sack.inspect}")
          return
        end
        # contents known is not open under the inventory feed, which lists a closed bag's too
        if Containers.listed?(container) && Containers.closed?(container) != true
          stow.opened(container)
          return
        end
        state = Containers.ensure_open(container)
        stow.opened(container) unless state == :unknown
        return if state == :nothing

        @context.sell_containers.push(container) unless @context.sell_containers.include?(container)
      end

      # Put an item in a bag.
      #
      # @param bag [GameObj]
      # @param item [GameObj]
      # @param is_skinner [Boolean] the item is a skinning tool, which is put
      #   away loose and noted for recovery
      # @return [Boolean, nil] whether it went in
      def store_item(bag, item, is_skinner = false)
        say('debug', "bag: #{bag.inspect} | item: #{item.inspect}")
        return if item.nil? || item.name == 'Empty'

        pending_stow = @on_tool_stow&.call(item, bag) if is_skinner

        result = stow.put(bag, item, loose: is_skinner)
        say('debug', "sacks_full(#{bag.name}) - item: #{item.inspect}") if result == :full
        %i[stored unlootable crumbled].include?(result)
      ensure
        pending_stow[:settled] = true if pending_stow && !Hands.holding?(item)
      end

      # Open the bags that close themselves.
      #
      # @return [void]
      def check_auto_closer
        settings[:auto_close].to_a.each { |bag_name| open_single_container(bag_name) }
      end

      # Open the bags loot is about to go into: the ones that close themselves,
      # now and then, and the bags for these items when bags are kept closed.
      #
      # @param item [Array<GameObj>] what is to be looted
      # @return [void]
      def open_loot_containers(item)
        say('debug', "item: #{item.inspect}")

        # makes sure any auto-closers are open before looting
        check_auto_closer if @autoclosers_due.nil? || @autoclosers_due.call

        # Early return if not keeping closed since they all get opened on startup
        return unless settings[:keep_closed]

        stow.bags_for(item).each { |bag| open_single_container(bag) }
      end

      # Give each hand back what it held when the pass began.
      #
      # @param drag [Proc, nil] given an item and "right" or "left", takes it
      #   into that hand; without one #drag is used
      # @return [void]
      def return_hands(drag: nil)
        before = [@context.right_hand, @context.left_hand]
        # Nothing to do
        return if before[0].id == GameObj.right_hand.id && before[1].id == GameObj.left_hand.id

        taking = drag || method(:drag)
        [['right', before[0], -> { GameObj.right_hand }], ['left', before[1], -> { GameObj.left_hand }]].each do |side, held, now|
          next if held.id.nil? || held.id == now.call.id

          if (ready_item = ready_key(held))
            Hands.ready(ready_item, held)
          else
            taking.call(held, side)
          end
        end
      end

      # --- putting an item away, by libeo's pickup, without a pause ------------

      # Put an item where the STOW list says. Unlike eloot's, it does not pause
      # when nothing has room: it says so.
      #
      # @param item [GameObj]
      # @param phase [Boolean] phase a box once it is put away
      # @param on_full [Symbol] accepted for the callers that pass it; this
      #   always signals
      # @return [Symbol, nil] :full when nothing has room, :no_default when no
      #   default bag is set, nil when it was put away
      def single_drag(item, phase = true, on_full: :signal, room_made: false) # rubocop:disable Lint/UnusedMethodArgument
        case pickup.drag(item, phase: phase, room_made: room_made)
        when :no_room then :full
        when :no_default then :no_default
        end
      end

      # @return [Boolean] whether the box went into a disk
      def single_drag_box(item) = pickup.drag_box(item)

      # Take an item into its bag with LOOT.
      def single_loot(item) = pickup.loot(item)

      private

      def settings = @context.settings

      def stow = @context.stow

      def say(type, text) = @context.say(type: type, text: text)

      def ready_key(item) = Hands.ready_key(item, keys: @context.original_readylist)

      def pickup
        @pickup ||= Pickup.new(@context, hands: self, command: @command, inventory: @inventory, wait_for_disk: @wait_for_disk)
      end
    end
  end
end
