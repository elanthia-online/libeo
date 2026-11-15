# frozen_string_literal: true

module EO
  # Wandering a hunting ground: one step to the adjacent room visited
  # least recently, by the map or, in the Elemental Confluence, by its
  # shifting exits; and finding and targeting a creature by name.
  #
  # The rooms visited are kept in $wander_rooms, the latest last, and
  # what has been learned of the Confluence in $mapdb_confluence_wayto and
  # the $mapdb_confluence_ globals, where other scripts read them.
  module Wander
    module_function

    # The compass, in turning order, for the Confluence outside GSIV.
    DIRS = %w[north northeast east southeast south southwest west northwest].freeze

    # Each direction's opposite.
    REVERSE_DIR = {
      'north' => 'south', 'northeast' => 'southwest',
      'east' => 'west', 'southeast' => 'northwest',
      'south' => 'north', 'southwest' => 'northeast',
      'west' => 'east', 'northwest' => 'southeast'
    }.freeze

    # The hot half of the Confluence. Room ids of GSIV (Prime) only.
    HOT_CONFLUENCE_ROOMS = [
      23282, 23283, 23284, 23285, 23286, 23287, 23288, 23289,
      23290, 23291, 23292, 23293, 23294, 23295, 23296, 23297,
      23298, 23299, 23300, 23301, 23302, 23303, 23329, 23330,
      23331, 23332, 23333, 23334
    ].freeze

    # Nouns of body parts, which are not creatures of their own.
    APPENDAGE_NOUN_RE = /^(?:arm|appendage|claw|limb|pincer|tentacle)s?$|^(?:palpus|palpi)$/i

    # The kraken tentacles that are creatures of their own.
    KRAKEN_TENTACLE_RE = /(?:amaranthine|ghostly|grizzled|ancient) kraken tentacle/i

    # The first live creature in the room matching any of the names, the
    # earlier name first. Animated creatures (but animated slush) and body
    # parts (but the named kraken tentacles) are passed over. It need not
    # be hostile; see hostile?.
    #
    # @param names [Array<String>] patterns for a creature's name
    # @return [GameObj, nil]
    def find_target(names)
      names.each do |name|
        found = GameObj.npcs.to_a.find do |npc|
          next if npc.status =~ /dead|gone/i

          # Skip animated NPCs (except animated slush)
          next if npc.name =~ /^animated\b/i && npc.name !~ /^animated slush/i

          # Skip appendage/arm nouns (except named kraken tentacles)
          next if npc.noun =~ APPENDAGE_NOUN_RE && npc.name !~ KRAKEN_TENTACLE_RE

          # Must match the requested name pattern
          next unless npc.name =~ /#{name}/i

          true
        end
        return found if found
      end
      nil
    end

    # @param npc [GameObj]
    # @return [Boolean] whether the creature is one of GameObj.targets
    def hostile?(npc)
      GameObj.targets.map(&:id).include?(npc.id)
    end

    # TARGET a creature, when it is hostile. One that is not, a town's
    # guard for one, is left untargeted.
    #
    # @param npc [GameObj]
    # @return [Boolean] whether TARGET was sent
    def target_npc!(npc)
      if GameObj.targets.map(&:id).include?(npc.id)
        fput("target ##{npc.id}")
        waitrt?
        true
      else
        false
      end
    end

    # @return [Array] the rooms visited, the latest last
    def wander_rooms
      $wander_rooms ||= []
    end

    # One step, by the way that fits the place.
    #
    # @param boundary [Array<String>] room ids not to step into
    # @param delay [Numeric] seconds to wait when there is nowhere to go
    # @return [void]
    def wander!(boundary:, delay:)
      if (checkroom == '[Elemental Confluence]') && (XMLData.game == 'GSIV')
        wander_gsiv_confluence!
      elsif checkroom == '[Elemental Confluence]'
        wander_other_confluence!
      else
        wander_standard!(boundary: boundary, delay: delay)
      end
    end

    # The room to step to next: an adjacent room not yet visited, any of
    # them; else the adjacent room visited longest ago. Never one across
    # a boundary, nor one whose way is closed for now (a scripted exit
    # whose time answers nil).
    #
    # @param room [Room] the room stood in
    # @param visited [Array<String>] room ids, the latest last
    # @param boundary [Array<String>] room ids not to step into
    # @return [String, nil] a room id; nil when there is nowhere to go
    def next_room(room, visited, boundary)
      options = room.wayto.keys - boundary
      # by its class, which the map's StringProc answers as Proc; it is
      # not one by is_a?
      options.delete_if { |room_id| (room.timeto[room_id].class == Proc) && room.timeto[room_id].call.nil? }

      unvisited = options.reject { |r| visited.include?(r) }
      unvisited.empty? ? visited.find { |r| options.include?(r) } : unvisited.sample
    end

    # One step by the map, to next_room. Waits for looting in progress
    # ($loot_grab_list, $loot_working) before moving.
    #
    # @param boundary [Array<String>] room ids not to step into
    # @param delay [Numeric] seconds to wait when there is nowhere to go
    # @return [void]
    def wander_standard!(boundary:, delay:)
      room = Room.current
      next_room = next_room(room, wander_rooms, boundary)
      return sleep(delay) if next_room.nil?

      wander_rooms.delete(next_room)
      wander_rooms.push(next_room)

      way = room.wayto[next_room]
      wait_while { ($loot_grab_list.to_a.length > 0) || $loot_working }

      if way.is_a?(String)
        move(way)
      elsif way.respond_to?(:call)
        way.call
      else
        sleep delay
      end
    end

    # One step in GSIV's Elemental Confluence, learning where each exit
    # leads as it goes: first an exit not yet tried, then one to a room
    # not yet visited, then to the room visited longest ago. What was
    # learned is thrown away when a room's exits have changed.
    #
    # @return [void]
    def wander_gsiv_confluence!
      $mapdb_confluence_wayto ||= {}

      begin
        start_room = Room.current
        wayto = ($mapdb_confluence_wayto[start_room.id] ||= {})

        raise "Restarting" if Room.current != start_room

        XMLData.room_exits.each { |d| wayto[d] = nil unless wayto.key?(d) }

        if wayto.keys != XMLData.room_exits
          raise "Restarting" if Room.current != start_room
          $mapdb_confluence_wayto = {}
          raise "Restarting"
        end

        # Priority: unexplored -> unvisited -> least-recently-visited
        dir = wayto.keys.find { |d| wayto[d].nil? }
        dir ||= wayto.keys.find { |d| !wander_rooms.include?(wayto[d]) }

        if dir.nil?
          next_id = wander_rooms.find { |i| wayto.values.include?(i) }
          dir = wayto.keys.find { |d| wayto[d] == next_id }
        end

        dir ||= XMLData.room_exits.sample

        result = move(dir.dup)
        if result == false
          status_tags
          look_result = dothistimeout('look', 5, /<compass>/)
          status_tags
          options = look_result.scan(/<dir value="(.*?)"/).flatten
          move(options.sample)
        else
          end_room = Room.current
          wander_rooms.delete(end_room.id)
          wander_rooms.push(end_room.id)
          wayto[dir] = end_room.id
          track_confluence_landmarks!(end_room)
        end
      rescue
        retry
      end
    end

    # One step in the Elemental Confluence of another game: the next
    # exit round the compass from the way come in by, kept in
    # $mapdb_confluence_last_dir.
    #
    # @return [void]
    def wander_other_confluence!
      if $mapdb_confluence_last_dir.nil?
        $mapdb_confluence_last_dir = XMLData.room_exits.sample
        result = move($mapdb_confluence_last_dir)
      else
        reverse_idx = DIRS.index(REVERSE_DIR[$mapdb_confluence_last_dir])
        idx = reverse_idx
        8.times do
          idx = (idx + 1) % 8
          if XMLData.room_exits.include?(DIRS[idx])
            $mapdb_confluence_last_dir = DIRS[idx]
            break
          end
        end
        result = move($mapdb_confluence_last_dir)
      end

      waitrt?

      # Handle stale exit data
      if result == false
        status_tags
        look_result = dothistimeout('look', 5, /<compass>/)
        options = look_result.scan(/<dir value="(.*?)"/).flatten
        $mapdb_confluence_last_dir = options.sample
        move($mapdb_confluence_last_dir)
      end
    end

    # Note where the Confluence's point of tranquility and bottomless pit
    # are, hot side and cold, in the $mapdb_confluence_ globals, and
    # forget one that is no longer where it was.
    #
    # @param end_room [Room] the room just entered
    # @return [void]
    def track_confluence_landmarks!(end_room)
      is_hot = HOT_CONFLUENCE_ROOMS.include?(end_room.id)

      has_tranquility = GameObj.loot.to_a.any? { |o| o.name == 'point of elemental tranquility' }
      has_pit         = GameObj.loot.to_a.any? { |o| o.name == 'gaping bottomless pit' }

      if is_hot
        if has_tranquility
          $mapdb_confluence_hot_tranquility = end_room.id
        elsif $mapdb_confluence_hot_tranquility == end_room.id
          $mapdb_confluence_hot_tranquility = nil
        end

        if has_pit
          $mapdb_confluence_hot_pit = end_room.id
        elsif $mapdb_confluence_hot_pit == end_room.id
          $mapdb_confluence_hot_pit = nil
        end
      else
        if has_tranquility
          $mapdb_confluence_cold_tranquility = end_room.id
        elsif $mapdb_confluence_cold_tranquility == end_room.id
          $mapdb_confluence_cold_tranquility = nil
        end

        if has_pit
          $mapdb_confluence_cold_pit = end_room.id
        elsif $mapdb_confluence_cold_pit == end_room.id
          $mapdb_confluence_cold_pit = nil
        end
      end
    end
  end
end
