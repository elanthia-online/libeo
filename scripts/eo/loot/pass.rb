# frozen_string_literal: true

module EO
  module Loot
    # One looting pass over a room, a step at a time: skin the dead, search
    # them, then loot the floor, and put the hands back as they were. #run is
    # the whole pass; a driver with its own loop calls #start, then #step until
    # it says :done, then #finish, and can act between steps. Every step ends
    # with what it handled put away, so the hands are free between steps; a
    # step that could not put something away says :no_room, naming it in #last.
    #
    # The inventory snapshot that tells which bags are full is taken once, at
    # the start of the floor, and is only a guide: a bag that has filled since
    # is found full when it is tried.
    class Pass
      # @return [GameObj, nil] the corpse or item the last step handled, or
      #   the one it could not put away
      attr_reader :last

      # @param context [EO::Loot::Context, #settings] the settings; it keeps
      #   what was in the hands when the pass began
      # @param floor [EO::Loot::Floor]
      # @param hands [#free_hand, #free_hands, #single_drag] what frees a hand
      #   and puts an item away (eloot's Inventory)
      # @param corpses [Array<GameObj>, Proc] the dead to skin and search, or
      #   a Proc that returns them when the pass needs them
      # @param skin [Proc, nil] returns the skinning pass (EO::Skinning::Pass)
      #   when skinning is to be done; nil skips it
      # @param floor_loot [Boolean] loot the floor too
      # @param stance [Proc] given a stance name, changes to it
      # @param coin_hand [Proc] uses the coin hand, when there is one
      # @param return_hands [Proc] gives each hand back what it held at the start
      # @param ready [Proc] runs as each pass starts, to look again at what
      #   may have changed since the last one (the disks)
      def initialize(context, floor:, hands:, corpses:, stance:, coin_hand:, return_hands:, skin: nil, floor_loot: true, ready: -> {})
        @context = context
        @floor = floor
        @hands = hands
        @corpses = corpses
        @skin = skin
        @floor_loot = floor_loot
        @stance = stance
        @coin_hand = coin_hand
        @return_hands = return_hands
        @ready = ready
        @phase = nil
        @last = nil
      end

      # The whole pass.
      #
      # @return [void]
      def run
        start
        loop { break if step == :done }
        finish
        nil
      end

      # Before the first step: the hands as they are, the loot stance, and
      # skinning set to begin. A character in a berserk cannot loot, and the
      # pass is over at once.
      #
      # @return [void]
      def start
        # a pass is run again room after room: nothing of the last one's
        # corpses or floor carries over
        @to_search = nil
        @any_corpses = nil
        @floor_state = nil
        @last = nil
        @phase = :done
        @ready.call
        if Spell['Berserk'].active?
          say('info', ' Berserk is active and preventing you from looting.')
          return
        end

        sleep 0.2

        # remember what is in our hands
        @context.right_hand = GameObj.right_hand
        @context.left_hand = GameObj.left_hand

        @stance.call(settings[:loot_stance])

        @skin_pass = @skin&.call
        @skin_pass&.start
        @phase = @skin_pass ? :skin : :search
      end

      # One piece of work.
      #
      # @return [Symbol] :skinned or :no_tool (a skinning group), :searched (a
      #   corpse), :special (an item that needed handling of its own),
      #   :looted (the ordinary loot, or one item of it), :no_room (something
      #   could not be put away; see #last), or :done
      def step
        start if @phase.nil?
        loop do
          result = send(:"step_#{@phase}")
          return result unless result == :next
        end
      end

      # After the pass, however it ended: up again from skinning and the weights
      # forgotten. The hands are not given back here; #restore_hands does that,
      # and the pass does it itself when it finishes its work.
      #
      # @return [void]
      def finish
        @skin_pass&.finish
        @floor.forget_weights
      end

      # Give each hand back what it held when the pass began.
      #
      # @return [void]
      def restore_hands = @return_hands.call

      private

      def settings = @context.settings

      def say(type, text) = @context.say(type: type, text: text)

      def step_skin
        result = @skin_pass.step
        return result unless result == :done

        @skin_pass.finish
        @phase = :search
        :next
      end

      def step_search
        @to_search ||= begin
          list = @corpses.respond_to?(:call) ? @corpses.call.to_a : @corpses.to_a
          @any_corpses = !list.empty?
          list.dup
        end

        while (thing = @to_search.shift)
          next unless Loot.searchable?(thing, exclude: @context.critter_exclude_regex)

          @stance.call(settings[:loot_stance])
          fput "raise ##{@context.blood_band.id} at ##{thing.id}" if settings[:use_bloodbands]
          results = Loot.search(thing, free: ->(hand) { free_hand(hand) }, stow: ->(item) { @hands.single_drag(item) },
                                       determination: settings[:sigil_determination_on_fail])
          say('debug', "Thing: #{thing.id}-#{thing.name}, Results: #{results.first}")
          @last = thing
          return stranded || :searched
        end

        # if the setting is on always end in the loot stance
        @stance.call(settings[:loot_stance]) if @any_corpses
        @phase = @floor_loot ? :floor : :wrap
        :next
      end

      def free_hand(hand) = hand == :left ? @hands.free_hands(left: true) : @hands.free_hand

      # The floor: the items that need handling of their own one at a time,
      # then the ordinary loot.
      def step_floor
        if @floor_state.nil?
          objs = @floor.room_candidates
          return end_floor if objs.empty?

          @floor.open_bags(objs)
          @pending = objs.dup
          @left = []
          @floor_state = :specials
        end

        if @floor_state == :specials
          while (thing = @pending.shift)
            if @floor.special(thing)
              @last = thing
              return stranded || :special
            end
            @left << thing
          end
          @floor_state = :regular
          @actions = @left.empty? ? [] : @floor.room_regular_steps(@left)
        end

        action = @actions.shift
        return end_floor unless action

        action.call
        @last = nil
        stranded || :looted
      end

      def end_floor
        @floor.forget_weights
        @phase = :wrap
        :next
      end

      # What the pass came for is done: the coin hand, and the hands as they were.
      def step_wrap
        # use coin hand if we have it
        @coin_hand.call
        @return_hands.call
        @phase = :done
        :done
      end

      def step_done = :done

      # A hand now holds something it did not at the start of the pass: the
      # last step could not put it away.
      #
      # @return [Symbol, nil] :no_room, with the item in #last
      def stranded
        held = [[GameObj.right_hand, @context.right_hand], [GameObj.left_hand, @context.left_hand]].find do |now, before|
          now&.id && now.id != before&.id
        end
        return nil unless held

        @last = held.first
        :no_room
      end
    end
  end
end
