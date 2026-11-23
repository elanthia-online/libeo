# frozen_string_literal: true

module EO
  module Guild
    # Bringing a lost child to a guard: the child, the town it wants and
    # the guards' rooms there, whether a room on the way is a danger to
    # it, waiting for it to catch up, the guard to report to, and the way
    # out of the Maaghara Labyrinth.
    module Rescue
      module_function

      # Who a child is reported to, as part of a pattern for a name.
      REPORTEE = 'sergeant|guard|purser|Belle|Luthrek'
      # What a child answers when asked where it lives, and the town.
      HOME = /The child says, "Please, take me home to ([^!]+?)!"/
      # The task failing, as the game announces it.
      FAILED = /^\[You have failed your current Adventurer's Guild task\.\]/

      # Climbing a root of the Maaghara Labyrinth: taken up and out, no way
      # to do it from this room now, and a slip to try again after.
      ROOT_UP = /rootlike tendrils as thick as your thumb snake out and encircle/
      ROOT_REFUSED = /seem to be any way to do that at the moment/
      ROOT_SLIPPED = /You step into the root, but can see no way to climb the slippery tendrils inside\.  After a moment, you step back out\./

      # The first child in the room.
      #
      # @return [String, nil] its id
      def child
        GameObj.npcs.to_a.each { |n|
          if n.noun =~ /child/i
            return n.id
          end
        }
        nil
      end

      # Look for a child for some seconds.
      #
      # @param seconds [Numeric]
      # @return [String, nil] its id
      def await_child(seconds = 5)
        found = nil
        timeout = Time.now + seconds
        while (found.nil? and timeout > Time.now)
          found = child
          sleep 0.1
        end
        found
      end

      # @param id [String] the child's id
      # @return [GameObj, nil] the child, when it is in the room
      def here(id)
        GameObj.npcs.to_a.find { |npc| npc.id == id }
      end

      # The rooms a child can be handed over in: the guards' rooms nearest
      # in each town, and those of Ta'Vaalor's gates.
      #
      # @return [Array<Integer>] room ids
      def dropoffs
        advguard = Map.current.find_all_nearest_by_tag("advguard")
        advguard2 = Map.current.find_all_nearest_by_tag("advguard2")
        advguard | advguard2 | [Map.ids_from_uid(4564003).first, Map.ids_from_uid(4564004).first, Map.ids_from_uid(4564010).first, Map.ids_from_uid(4564005).first, Map.ids_from_uid(4564011).first, Map.ids_from_uid(4564008).first, Map.ids_from_uid(4564006).first, Map.ids_from_uid(4564007).first, Map.ids_from_uid(4564013).first, Map.ids_from_uid(4564014).first, Map.ids_from_uid(4564009).first]
      end

      # A room in each town a child names, to find its guards from.
      #
      # @return [Hash{String => Integer}] the town as the child says it,
      #   and a room id
      def homes
        {
          "Icemule Trace"        => Map.ids_from_uid(4042150).first,
          "Kharam Dzu"           => Map.ids_from_uid(3001025).first,
          "Kraken's Fall"        => Map.ids_from_uid(7118221).first,
          "Mist Harbor"          => Map.ids_from_uid(3201029).first,
          "the County of Torre"  => Map.ids_from_uid(2101008).first,  # River's Rest
          "Vornavis"             => Map.ids_from_uid(4209030).first,  # Solhaven
          "Ta'Illistim"          => Map.ids_from_uid(13100042).first,
          "Ta'Vaalor"            => Map.ids_from_uid(14100047).first,
          "Wehnimer's Landing"   => Map.ids_from_uid(7120).first,
          "Kharag 'doth Dzulthu" => Map.ids_from_uid(13006016).first, # Zul Logoth
          "Kharam-Dzu"           => Map.ids_from_uid(3001025).first,  # Teras Isle
        }
      end

      # Ask the child where it lives.
      #
      # @return [String, nil] the town as the child says it; nil when it
      #   does not answer
      def ask_home
        line = dothistimeout 'ask child about destination', 5, HOME
        Regexp.last_match(1) if line =~ HOME
      end

      # Whether the room holds creatures to be stopped before the child
      # comes through: something to target that is not known to be
      # untargetable, no other character, nobody to report to, and more
      # here than the child alone.
      #
      # @param id [String] the child's id
      # @param untargetable [Array<String>] names of creatures not counted
      # @return [Boolean]
      def threat?(id, untargetable)
        if GameObj.targets.any? and !checkpcs and GameObj.targets.any? { |npc| !untargetable.include?(npc.name) } and !(GameObj.npcs.to_a.any? { |npc| npc.name =~ /#{REPORTEE}/i } or GameObj.room_desc.to_a.any? { |i| i.name =~ /purser/ })
          unless GameObj.npcs.to_a.size == 1 and GameObj.npcs.to_a.find { |npc| npc.id == id }
            return true
          end
        end
        false
      end

      # Wait for the child to come into the room, or for the room to
      # change. In a room of no_wait, five seconds is long enough.
      #
      # @param id [String] the child's id
      # @param no_wait [Array<Integer>] room ids
      # @return [void]
      def await(id, no_wait)
        thisroom = Map.current.id
        timeout = Time.now + 5
        wait_until { GameObj.npcs.to_a.find { |npc| npc.id == id } or (Time.now > timeout and no_wait.include?(Room.current.id)) or thisroom != Room.current.id }
      end

      # @return [GameObj, nil] someone in the room a child is reported to
      def reportee
        [GameObj.npcs.to_a.find { |creature| creature.name =~ /#{REPORTEE}/i }, GameObj.room_desc.to_a.find { |i| i.name =~ /#{REPORTEE}/ }].find { |i| i }
      end

      # The rooms of the Maaghara Labyrinth with a root to climb, and for
      # each the room to try next when its root will not be climbed.
      #
      # @return [Hash{Integer => Integer}] room ids
      def maaghara_exits
        {
          Map.ids_from_uid(13022005).first => Map.ids_from_uid(13022015).first,
          Map.ids_from_uid(13022025).first => Map.ids_from_uid(13022015).first,
          Map.ids_from_uid(13022015).first => Map.ids_from_uid(13022035).first,
          Map.ids_from_uid(13022035).first => Map.ids_from_uid(13022045).first,
          Map.ids_from_uid(13022045).first => Map.ids_from_uid(13022005).first
        }
      end

      # GO ROOT, again after a slip. Taken up, wait to arrive outside the
      # labyrinth and stand.
      #
      # @return [Symbol] :out; :refused when there is no climbing it from
      #   this room; :failed after three tries without an answer
      def climb_root
        maaghara_counter = 0
        loop do
          break if maaghara_counter == 3
          move_result = dothistimeout "go root", 3, Regexp.union(ROOT_UP, ROOT_REFUSED, ROOT_SLIPPED)
          if ROOT_UP.match(move_result)
            wait_while { Map.current.id != Map.ids_from_uid(13021008).first }
            EO.stand
            return :out
          elsif ROOT_REFUSED.match(move_result)
            return :refused
          elsif ROOT_SLIPPED.match(move_result)
            sleep(1) # climb check failed, wait a second to retry
            next
          elsif move_result.nil?
            echo "maaghara_move failed"
            maaghara_counter += 1
          end
        end
        :failed
      end
    end
  end
end
