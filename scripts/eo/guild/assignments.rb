# frozen_string_literal: true

module EO
  module Guild
    # The visits that turn a task into its details: the furrier, herbalist
    # or gem dealer who wants something, and the guards who say what a task
    # is or take one back.
    #
    # Commands, walks, waits and messages go through the running script's
    # helpers (EO.use). The helpers this needs: result(text, pattern)
    # answering one line, go(place), wait(), and say(type, text).
    module Assignments
      module_function

      ATTEMPTS = 5

      # Who is asked for each kind of task, and how their room is found from
      # the town's.
      KINDS = {
        'furrier'   => { names: Tables::FURRIER_NAMES, room: ->(town) { town.find_nearest_by_tag('furrier') } },
        'herbalist' => { names: Tables::HERBALIST_NAMES, room: ->(town) { town.find_nearest(Tables.herbalist_rooms) } },
        'jeweler'   => { names: Tables::JEWELER_NAMES, room: ->(town) { town.find_nearest_by_tag('gemshop') } }
      }.freeze

      # What a guard says when he has nothing for the character.
      GUARD_NOTHING = /I don't have any tasks for you right now|Try bugging me later|Who are you trying to ask\?/
      # Who answers for the guard, town by town.
      GUARD_NAMES = /(?:guard|sergeant|guardsman|sentry|tavernkeeper|alchemist|Malovor)/i
      # The Hinterwilds tavernkeeper wanders: from his rooms the alchemist
      # is asked instead.
      TAVERNKEEPER_UIDS = /7503252|7503251/
      HINTERWILDS_ALCHEMIST = 'u7503253'
      # A task whose heirloom has been found and is to be brought back.
      LOCATED = /You have located (?:a |an )?(.*?) and should bring (?:it back|your find)/i

      # Walk to the furrier, herbalist or gem dealer of the task's town and
      # ask about the bounty until the task's text changes.
      #
      # @param kind [String] a key of KINDS
      # @param town [Room] the task's town
      # @return [Symbol] :done; :no_npc (nobody to ask was found); or
      #   :gave_up after ATTEMPTS asks changed nothing
      def ask(kind, town)
        spec = KINDS.fetch(kind)
        attempts = 0

        EO.go2(spec[:room].call(town))
        EO.settle

        original = checkbounty

        begin
          attempts += 1

          npc = NPCs.find(spec[:names])
          return :no_npc if npc.nil?

          fput "ask ##{npc.id} about bounty"

          raise 'Bounty did not change' unless Taskmaster.changed?(original)

          :done
        rescue StandardError
          return :gave_up unless attempts < ATTEMPTS

          EO.say('yellow', "Bounty type did not change, retrying (attempt #{attempts})...")
          EO.settle
          retry
        end
      end

      # Visit the town's guards in turn until one has something to say. A
      # task that says its heirloom was found has the heirloom taken out
      # into the right hand first, from the first container that has it.
      #
      # @param rooms [Array<Integer>] the guard rooms, from NPCs.guard_rooms
      # @param containers [Array<GameObj>] where a found heirloom may be
      # @param open [Proc] given a container, sees it open
      # @param missing [Proc] called when the heirloom is in none of them;
      #   answering :stop ends the visit
      # @return [Boolean] whether the task's text changed; false when the
      #   visit was stopped
      def ask_guards(rooms, containers:, open:, missing:)
        original = checkbounty
        guards = []
        need_fill_hands = false

        rooms.each do |room|
          room = HINTERWILDS_ALCHEMIST if Room[room].uid.first.to_s =~ TAVERNKEEPER_UIDS

          EO.go2(room)

          if Room.current.location =~ /the town of River's Rest/
            guards.push('purser')
          else
            guards = (GameObj.room_desc.to_a + GameObj.npcs.to_a).find_all { |npc| npc.name =~ GUARD_NAMES }
          end

          next if guards.empty?

          if checkbounty =~ LOCATED
            requested_item = Regexp.last_match(1)
            found_item = nil

            containers.each do |container|
              open.call(container)

              found_item = container.contents.find { |item| item.name.match?(/#{requested_item}/) }
              break if found_item
            end

            if found_item
              empty_hands
              need_fill_hands = true
              EO.result("_drag ##{found_item.id} right", Tables::GET_RESULT)
            elsif missing.call == :stop
              return false
            end
          end

          got_response = false
          guards.each do |guard|
            result = EO.result("ask #{guard} about bounty", Tables::GUARD_RESPONSES)
            unless result =~ GUARD_NOTHING
              got_response = true
              break
            end
          end

          break if got_response

          fput 'stow right' if checkright
        end

        fill_hands if need_fill_hands

        Taskmaster.changed?(original)
      end
    end
  end
end
