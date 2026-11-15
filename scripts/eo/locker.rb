# frozen_string_literal: true

module EO
  # Lockers: which rooms hold a character's locker, the last step into a
  # booth, what the game says when it will not let you in, and opening the
  # locker once inside.
  #
  # Commands go through the running script's helpers (EO.use). The helper
  # this needs: command(text, pattern, silent:, quiet:) answering the lines.
  module Locker
    module_function

    # Rounds of trying every locker before giving up, and seconds between rounds.
    MAX_PASSES = 6
    PASS_WAIT = 10

    # The game's refusal when the character's one locker is in another town.
    ELSEWHERE = /your locker isn't here/i
    # LOCKER INFO's line naming the town a locker is in.
    INFO = /Your locker is currently located in (.+?)\./i
    # The game's refusal while the character owes a debt.
    DEBT = /pay off (your|that) debt/i

    # A way into, or out of, a locker booth.
    WAY = /^(?:opening|curtain|tapestry)$/

    # A house's own lockers in a town, as the map tags them: the locker
    # rooms themselves, or when none are mapped, the entrances to them.
    #
    # @param rooms [Array<Room>] the map
    # @param che [String, nil] the character's house
    # @param town_id [Integer] the town's room id
    # @return [Array<Room>] none for a character with no house
    def che_rooms(rooms, che, town_id)
      return [] if che.to_s.empty? || che.to_s == 'none'

      %w[locker entrance_locker].each do |tier|
        # the tag first: the town lookup is slow, and few rooms are this house's
        found = rooms.select { |room| room.tags.include?("meta:che:#{che}:#{tier}") }
                     .select { |room| room.find_nearest_by_tag('town') == town_id }
        return found unless found.empty?
      end

      []
    end

    # One name for a place the game and the map name differently: "the town
    # of Kraken's Fall" and "Kraken's Fall"; Teras Isle, which the map calls
    # Kharam-Dzu; the Isle of Four Winds, whose lockers the map puts in Mist
    # Harbor; and the house lounge lockers reached from Ta'Illistim, in a
    # hidden area the map calls the Lost Home.
    #
    # @param name [String]
    # @return [String]
    def town_name(name)
      plain = name.to_s.strip.sub(/\Athe (?:town|city|village|free port|tunnels and caverns|isle) of /i, '').downcase
      { 'teras isle' => 'kharam-dzu', 'four winds' => 'mist harbor', 'the lost home' => "ta'illistim" }.fetch(plain, plain)
    end

    # The town a house's lockers are in, by the town's name as LOCKER INFO
    # gives it.
    #
    # @param rooms [Array<Room>] the map
    # @param che [String, nil] the character's house
    # @param town [String]
    # @return [Integer, nil] the town's room id, nil when the house has no
    #   mapped lockers there
    def che_town_id(rooms, che, town)
      return nil if che.to_s.empty? || che.to_s == 'none' || town.to_s.strip.empty?

      wanted = town_name(town)
      found = rooms.find do |room|
        room.tags.any? { |tag| tag =~ /\Ameta:che:#{Regexp.escape(che.to_s)}:(?:locker|entrance_locker)\z/ } && town_name(room.location) == wanted
      end

      found && found.find_nearest_by_tag('town')
    end

    # Where a house member's one locker is, asked of LOCKER INFO.
    #
    # @return [String, nil] the town as the game names it
    def info_town
      lines = EO.command('locker info', /Your locker is currently located in .+?\.|<prompt time=".*?">&gt;<\/prompt>/, silent: true, quiet: true)
      lines.join(' ')[INFO, 1]
    end

    # The lines that arrived after +before+ was read. Both are the last
    # lines of the session, so the new ones follow the longest run of
    # +before+'s end that +after+ begins with.
    #
    # @param before [Array<String>]
    # @param after [Array<String>]
    # @return [Array<String>]
    def lines_since(before, after)
      overlap = [before.length, after.length].min.downto(0).find { |count| before.last(count) == after.first(count) }
      after[overlap..]
    end

    # The rooms that can be reached, nearest first.
    #
    # @param rooms [Array<Room>]
    # @return [Array<Room>]
    def nearest_first(rooms)
      return rooms if rooms.empty?

      # no destination list: given one, dijkstra stops at the first of them
      # it reaches and the rest have no distance
      _previous, distances = Room.current.dijkstra
      distances ||= {}
      rooms.select { |room| distances[room.id] }.sort_by { |room| distances[room.id] }
    end

    # The command for the opening, curtain or tapestry here, the way into a
    # booth from outside and out of it from inside.
    #
    # @return [String, nil] nil when the room shows none
    def way
      way_obj = (GameObj.loot.to_a + GameObj.room_desc.to_a).find { |obj| obj.noun =~ WAY }
      return nil if way_obj.nil?

      way_obj.noun = 'opening' if way_obj.noun == 'tapestry'
      "go #{way_obj.noun}"
    end

    # @return [Boolean] whether the room shows a locker or a counter
    def inside?
      (GameObj.room_desc.to_a + GameObj.loot.to_a).any? { |obj| obj.name =~ /locker|counter/ }
    end

    # @param place [Room]
    # @return [Boolean] whether the map tags the room as a booth itself,
    #   not the room outside one
    def booth?(place)
      place.tags.any? { |tag| tag =~ /\Ameta:che:[^:]+:locker\z/ }
    end

    # The last step of the way to a booth: a booth that is taken refuses the
    # step, which a walker treats as a broken route, so the caller walks to
    # the room before and takes this step itself.
    #
    # @param place [Room] the booth
    # @return [Array(Integer, Object), nil] the room before the booth and
    #   the map's move into it; nil when there is no such plain last step
    def approach(place)
      # a single destination, so dijkstra stops on reaching the booth
      previous, _distances = Room.current.dijkstra(place.id)
      before = previous && previous[place.id]
      return nil if before.nil? || before == place.id

      way = Room[before]&.wayto&.[](place.id.to_s)
      way && [before, way]
    end

    # Take a move from the map: a command, or a scripted move.
    #
    # @param way [String, #call]
    # @param place [Room] where it leads
    # @return [Boolean, nil] true once in the room; false or nil when the
    #   game refused. For a command it is what move answers, which is nil
    #   for a booth someone is using.
    def step(way, place)
      return move(way) if way.is_a?(String)

      way.call
      20.times do
        break if Room.current.id == place.id

        sleep 0.05
      end
      Room.current.id == place.id
    end

    # The debt the character owes, which WEALTH mentions.
    #
    # @return [Integer, nil] nil when WEALTH names none
    def debt
      lines = EO.command('wealth quiet', /^You have (no|[,\d]+|but one) silver with you/, silent: true, quiet: true).join(' ')
      return nil unless lines.to_s =~ /In the back of your mind you remember you owe a debt of ([\d,]+) silver/

      Regexp.last_match(1).gsub(',', '').to_i
    end

    # OPEN LOCKER.
    #
    # @return [Array<String>] the answer's lines
    def open
      EO.command('open locker', /exist=".*?" noun="(?:locker|chest)"|That is already open.|<prompt time=".*?">&gt;<\/prompt>/)
    end

    # The container in an open locker whose name matches, on the floor or
    # on the room's counter.
    #
    # @param name [String] the container's name, as a pattern
    # @return [GameObj, nil]
    def stash(name)
      found = GameObj.loot.find { |item| item.name =~ /#{name}/ }
      return found unless found.nil?

      counter = GameObj.room_desc.find { |item| item.name =~ /counter/ }
      EO.command("look on ##{counter.id}", /<container id='.*?' title=/, silent: true, quiet: true)
      counter.contents.find { |item| item.name =~ /#{name}/ }
    end

    # @return [GameObj, nil] the thing in the room that shows this is a locker
    def here
      GameObj.loot.find { |item| item.name =~ /dark stained antique oak trunk|counter|locker/ }
    end
  end
end
