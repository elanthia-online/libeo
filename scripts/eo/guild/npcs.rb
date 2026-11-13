# frozen_string_literal: true

module EO
  module Guild
    # Finding the guild's people: someone in the room by name, the
    # taskmaster, and a town's guards.
    #
    # Walks and waits go through the running script's helpers (EO.use). The
    # helpers this needs: go(place), wait(), and say(type, text).
    module NPCs
      module_function

      # Someone in the room whose name matches, looked for five times with
      # a wait between: what the room shows can lag behind arriving in it.
      #
      # @param names [Regexp]
      # @return [GameObj, nil] nil when nobody matched
      def find(names)
        EO.say('debug', " find_npc | caller: #{caller(1..1).first}")

        readable = names.source.gsub('(?i-mx:', '').gsub(')', '')
        npc = nil

        (1..5).each do |attempt|
          npc = (GameObj.room_desc.to_a + GameObj.npcs.to_a).find { |t| t.name =~ names }
          break if npc

          echo
          EO.say('yellow', "Trying to detect NPC: #{readable} (attempt #{attempt})") if attempt > 1
          echo

          EO.settle
        end

        npc
      end

      # Go to the guild unless already there, and name the taskmaster to
      # ask: Taskmaster; Halfwhistle in the Hinterwilds; or First Mate
      # Seldit on Sailor's Grief, who wanders the boat and is looked for
      # through it three times.
      #
      # @return [String, nil] nil when Seldit was not found
      def taskmaster
        EO.say('debug', " find_taskmaster | caller: #{caller(1..1).first}")

        boat = Tables::SAILORS_GRIEF_UIDS
        current_room = Room.current.uid.first

        unless Room.current.tags.include?('advguild') || boat.include?(current_room)
          EO.go2('advguild')
          EO.settle
          current_room = Room.current.uid.first
        end

        return 'Halfwhistle' if current_room == Tables::HINTERWILDS_GUILD_UID
        return 'Taskmaster' unless boat.include?(current_room)

        return 'Seldit' if GameObj.npcs.any? { |npc| npc.name =~ /Seldit/i }

        3.times do
          boat.each do |spot|
            EO.go2("u#{spot}")
            return 'Seldit' if GameObj.npcs.any? { |npc| npc.name =~ /Seldit/i }

            echo "Looking for the lousy First Mate Seldit in #{spot}"
          end
        end

        nil
      end

      # The rooms with a guard of the adventurer's guild that belong to a
      # town and can be walked to from it.
      #
      # @param town [String] the task's town
      # @param towns [Hash{String => String}] Tables.town_uids
      # @return [Array<Integer>] room ids
      def guard_rooms(town, towns = Tables.town_uids)
        square = Room[towns[town]]
        places = Room.list.find_all do |r|
          r.tags.any? { |tag| tag =~ /advguard/ } && !r.tags.to_s.empty? && Room[r.find_nearest_by_tag('town')] == square && !square.path_to(r).nil?
        end.map(&:id)

        EO.say('debug', "town: #{square} | guard_list places: #{places}")
        places
      end
    end
  end
end
