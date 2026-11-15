# frozen_string_literal: true

module EO
  module Guild
    # Where a task is to be done: the rooms of the place it names, the one
    # to start from, the rooms around it not to cross into, and a room id
    # from either way a setting can write one.
    #
    # Messages go through the running script's say(type, text) (EO.use).
    module Location
      module_function

      # The most rooms hunted within one place. A larger place is cut down
      # to a connected part of this size around the nearest room.
      MAX_ROOMS = 100

      # A room id from a setting: a map id, or "u" and a uid.
      #
      # @param room [String]
      # @return [Integer, nil] nil for a uid the map does not have
      def room_id(room)
        if (m = /u(?<uid>\d+)/.match(room))
          lookup_id = Map.ids_from_uid(m[:uid].to_i)
          return nil unless lookup_id.size > 0

          room = lookup_id[0]
        end
        room.to_i
      end

      # The rooms of a place, the one to start from and the rooms just
      # outside it. A room belongs when its location and the place's name
      # match either way round.
      #
      # @param location [String] the place a task names
      # @param bad_rooms [Array<Integer>] rooms left out of every place
      # @return [Array(String, String), nil] the start room's id, and the
      #   boundary rooms' ids joined by commas; nil when no room belongs
      def find(location, bad_rooms: [])
        EO.say('debug', " find_location | caller: #{caller(1..1).first}")

        boundary_list = []
        location_list = []

        Room.list.each do |r|
          location_list.push(r.id) if !r.location.to_s.empty? && (location.to_s =~ /#{r.location}/i || r.location.to_s =~ /#{location}/i) && !bad_rooms.include?(r.id)
        end
        return nil if location_list.empty?

        location_start = Room.current.find_nearest(location_list)

        if location_list.size > MAX_ROOMS
          EO.say('debug', " find_location: capping #{location_list.size} location rooms to #{MAX_ROOMS}")
          location_list = limit(location_start, location_list)
        end

        EO.say('debug', " find_location: location_list - #{location_list}")
        location_list.each do |id|
          Room[id].wayto.each_key do |room|
            next if location_list.include?(room.to_i)

            boundary_list.push(room.to_s)
          end
        end
        EO.say('debug', "Bandits: boundary_list - #{boundary_list}")

        [location_start.to_s, boundary_list.join(',')]
      end

      # A connected part of a place, found by walking outward from a room
      # and keeping to the place's rooms.
      #
      # @param start_id [Integer, String] the room to walk out from
      # @param location_list [Array<Integer>] every room of the place
      # @param max_rooms [Integer]
      # @return [Array<Integer>] at most max_rooms of them
      def limit(start_id, location_list, max_rooms = MAX_ROOMS)
        selected = []
        queued = [start_id.to_i]

        until queued.empty? || selected.size >= max_rooms
          current = queued.shift
          next if selected.include?(current)

          selected.push(current)
          Room[current].wayto.each_key do |room|
            neighbor = room.to_i
            next if selected.include?(neighbor) || queued.include?(neighbor)
            next unless location_list.include?(neighbor)

            queued.push(neighbor)
          end
        end

        selected
      end
    end
  end
end
