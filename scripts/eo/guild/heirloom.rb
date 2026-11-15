# frozen_string_literal: true

module EO
  module Guild
    # Searching for a lost heirloom: the spells before a search, the search
    # and what it turns up, and the step to the next room.
    #
    # The options are a character's heirloom options: a list of names such
    # as "use_213" and "run".
    #
    # Commands go through the running script's helpers (EO.use). The helpers
    # this needs: result(text, pattern) answering one line, and wait().
    module Heirloom
      module_function

      # A task whose heirloom has been found.
      LOCATED = /You have located/

      # The spells cast before a search, those the options allow.
      #
      # @param options [Array<String>]
      # @param creatures [Array<GameObj>] what Mass Calm (619) has been cast
      #   on already; added to
      # @return [void]
      def spells(options, creatures)
        Forage.cast(213) if Stats.prof =~ /Cleric|Empath/i && options.include?('use_213') && !Forage.sanctuary?
        Forage.cast(1011) if options.include?('use_1011') && !Forage.song_of_peace?
        Forage.cast(709) if options.include?('use_709') && !GameObj.targets.any? { |c| c.name =~ /arm/ } && !GameObj.targets.empty?

        Forage.cast(402) if !Effects::Buffs.active?('Presence') && options.include?('use_402')
        Forage.cast(506) if !Effects::Buffs.active?('Celerity') && !Effects::Cooldowns.active?('Celerity') && options.include?('use_506')
        Forage.cast(919) if !Effects::Buffs.active?("Wizard's Shield") && !Effects::Cooldowns.active?("Wizard's Shield") && options.include?('use_919')
        Forage.cast(140) if !Effects::Buffs.active?('Wall of Force') && !Effects::Cooldowns.active?('Wall of Force') && options.include?('use_140')
        Forage.cast(1035) if !Effects::Buffs.active?('Song of Tonis') && options.include?('use_1035')

        return unless !GameObj.targets.empty? && options.include?('use_619')

        targets = GameObj.targets.reject { |w| creatures.any? { |c| c.id == w.id } }
        Forage.cast(619) if targets.length.positive?
        creatures.concat(targets)
        sleep 0.5
        waitcastrt?
      end

      # Kneel, SEARCH with the hands empty, stand, and put away what the
      # search put in the right hand, or the heirloom if it lies on the ground.
      #
      # @param item [String] the heirloom, as a pattern for its name
      # @return [void]
      def search(item)
        until kneeling?
          fput 'kneel'
          sleep 0.2
        end

        empty_hands if checkleft || checkright

        fput 'search'
        EO.settle

        fput 'stand' until standing?
        EO.settle

        if checkright
          EO.result("stow ##{GameObj.right_hand.id}", Tables::PUT_RESULT)
        else
          heirloom = GameObj.loot.find { |obj| obj.name =~ /#{item}/ }

          if heirloom
            EO.result("_drag ##{heirloom.id} right", Tables::GET_RESULT)
            EO.result("stow ##{heirloom.id}", Tables::PUT_RESULT)
          end
        end
      end

      # One step to a neighbouring room not yet visited, else to the one
      # visited longest ago, never across a boundary.
      #
      # @param visited [Array<String>] room ids, the latest last; added to
      # @param boundaries [Array<String>] room ids not to step into
      # @return [void]
      def wander(visited, boundaries)
        room = Room.current
        next_room_options = room.wayto.keys - boundaries
        next_room_options.delete_if { |room_id| (room.timeto[room_id].class == Proc) and room.timeto[room_id].call.nil? }
        next_room = next_room_options.find_all { |r| !visited.include?(r) }
        next_room = if next_room.empty?
                      visited.find { |r| next_room_options.include?(r) }
                    else
                      next_room[rand(next_room.length)]
                    end
        visited.delete(next_room)
        visited.push(next_room)
        way = room.wayto[next_room]
        if way.class == String
          move(way)
        else
          way.call
        end
      end
    end
  end
end
