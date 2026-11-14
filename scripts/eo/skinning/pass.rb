# frozen_string_literal: true

module EO
  module Skinning
    # Skinning the dead for one looting pass, a tool group at a time: the
    # edged group first, then the blunt one. #run is the whole pass; a driver
    # with its own loop calls #start, then #step until it says :done, then
    # #finish, and can act between steps. A step ends with the tool put away
    # and the corpses of its group tried, so the hands are free between steps;
    # the character may still be kneeling until #finish.
    class Pass
      # @return [Array<GameObj>] the corpses the steps went through so far
      attr_reader :skinned

      # @param context [EO::Loot::Context, #settings] the settings, the
      #   weapon inventory, where to say something and to save
      # @param corpses [Array<GameObj>] the dead to consider
      # @param hands [#free_hand, #free_hands, #drag, #store_item] what frees
      #   a hand, draws the tool and puts it away (eloot's Inventory)
      # @param ensure_items [Proc] given key:, list:, inventory: and
      #   check_hidden:, finds the listed skinning weapon or sheath again
      #   when the lists changed
      def initialize(context, corpses:, hands:, ensure_items:)
        @context = context
        @corpses = corpses
        @hands = hands
        @ensure_items = ensure_items
        @skinned = []
        @groups = nil
      end

      # The whole pass. A pass an error ends is not finished here: what the
      # caller does after one (eloot's room recovery stands up itself) is
      # its own; a driver that leaves a pass calls #finish.
      #
      # @return [Array<GameObj>] the corpses skinned
      def run
        start
        loop { break if step == :done }
        finish
        skinned
      end

      # Decide which corpses are worth a try and with which tool. With a
      # skinning bounty set to be the only reason to skin, that creature only.
      #
      # @return [void]
      def start
        @groups = []
        creature = nil
        if settings[:skin_bounty_only]
          return unless Bounty.task.skin?

          creature = Bounty.task.creature.to_s
        end

        edged, blunt = Skinning.choose(@corpses, unskinnable: settings[:unskinnable],
                                                 exclude: Skinning.exclusions(settings), creature: creature)
        @groups = [[:normal, edged], [:blunt, blunt]].reject { |_, objs| objs.empty? }
        @standing_needed = !@groups.empty?
      end

      # Skin the next tool group.
      #
      # @return [Symbol] :skinned (the group was tried with its tool),
      #   :no_tool (none listed, or it could not be drawn: the group is
      #   left), or :done (no group is left)
      def step
        start if @groups.nil?
        kind, objs = @groups.shift
        return :done if kind.nil?

        skin_group(objs, blunt: kind == :blunt) ? :skinned : :no_tool
      end

      # After the pass, however it ended: up again, in the stance it was in.
      #
      # @return [void]
      def finish
        return unless @standing_needed

        @standing_needed = false
        Skinning.stand_up
      end

      private

      def settings = @context.settings

      def say(type, text) = @context.say(type: type, text: text)

      # @return [Boolean] whether the group was skinned
      def skin_group(objs, blunt:)
        weapon_key = blunt ? 'skin_weapon_blunt' : 'skin_weapon'
        sheath_key = blunt ? 'skin_sheath_blunt' : 'skin_sheath'
        # Check skinner and sheath in case ReadyList/StowList got updated
        @ensure_items.call(key: weapon_key, list: ReadyList.ready_list, inventory: @context.weapon_inv)
        @ensure_items.call(key: sheath_key, list: ReadyList.ready_list, check_hidden: true)

        skinner = Skinning.tool(ReadyList.ready_list, blunt: blunt)
        if skinner.nil?
          what = blunt ? 'No blunt weapon found' : 'No edged skinning weapon found and nothing in your right hand'
          say('info', " #{what}. Please run setup and make sure it's listed.")
          return false
        elsif ReadyList.ready_list[weapon_key.to_sym].to_s.empty?
          say('info', ' No edged skinning weapon found. Using your right hand.')
        end
        say('debug', "#{blunt ? 'blunt' : 'edged'} skinner: #{skinner.inspect}")

        free = ->(hands) { hands == :both ? @hands.free_hands(both: true) : @hands.free_hand }
        put_away = lambda do |tool|
          @hands.store_item(Skinning.sheath(ReadyList.ready_list, blunt: blunt) || StowList.stow_list[:default], tool, true)
          @hands.store_item(StowList.stow_list[:default], tool) if Hands.holding?(tool)
        end

        done = false
        Skinning.with_tool(skinner, blunt: blunt, free: free, draw: ->(tool) { @hands.drag(tool) }, put_away: put_away) do |hand|
          Skinning.prepare(kneel: settings[:skin_kneel], resolve: settings[:skin_resolve], nature: settings[:skin_604])
          learn(Skinning.skin(objs, hand: hand))
          @skinned.concat(objs)
          done = true
        end
        done
      end

      # Names the game said cannot be skinned, kept for the next run.
      def learn(names)
        return if names.empty?

        settings[:unskinnable].push(*names)
        settings[:unskinnable].uniq!
        @context.save
      end
    end
  end
end
