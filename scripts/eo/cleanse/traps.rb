# frozen_string_literal: true

module EO
  module Cleanse
    # The Hive's traps, which are searched out and disarmed where they went
    # off, and the itchy curse, which is waited out somewhere safe.
    #
    # Commands go through the running script's helpers (EO.use). The helpers
    # this needs: command(text, pattern) answering the lines, and wait().
    module Traps
      module_function

      # Rolled SEARCH tries, and DISARM tries on an apparatus found.
      SEARCH_ATTEMPTS = 3
      DISARM_ATTEMPTS = 3
      # Seconds a search, or a disarming, may take in all.
      DEADLINE = 20

      # Every outcome of SEARCH: an answer not listed here is never seen,
      # and could not be told from no answer.
      SEARCH_RESULT = Regexp.union(
        /d100: /,
        /You don't find anything of interest here/,
        /You can't see well enough to search around/
      )
      # Every outcome of DISARM APPARATUS.
      DISARM_RESULT = Regexp.union(
        /d100: /,
        /You want to disarm what\?/,
        /You can't see well enough/
      )

      # The line that says the itchy curse has passed.
      RASH_GONE = /You no longer feel so defenseless and the rash seems to disappear\./

      # Whether the character is still in the room a trap went off in. An
      # unmapped room has no id, and two of those are not taken for the same
      # room. Ids are compared where there are any: a reloaded map makes new
      # room objects for the same rooms.
      #
      # @param trap_room [Room, nil]
      # @return [Boolean]
      def here?(trap_room)
        current = Room.current
        return false if trap_room.nil? || current.nil?
        return trap_room.id == current.id unless trap_room.id.nil? || current.id.nil?

        trap_room == current
      end

      # SEARCH for a trap until it is found or there is no going on.
      #
      # @param trap_room [Room] where the trap went off
      # @return [Symbol] :found (a Success, the trap shown or disturbed),
      #   :clear (nothing here), :blind (too dark to search), :moved (no
      #   longer in that room), :muckled (dead, stunned, webbed, bound or
      #   asleep), :exhausted (out of tries), or :timeout
      def search(trap_room)
        deadline = Time.now + DEADLINE
        attempts = 0

        loop do
          return :moved unless here?(trap_room)
          return :muckled if dead? || muckled?
          return :timeout if Time.now > deadline
          return :exhausted if attempts >= SEARCH_ATTEMPTS

          EO.settle
          attempts += 1
          lines = EO.command('search', SEARCH_RESULT)

          return :blind if lines.any? { |line| line =~ /You can't see well enough to search around/ }
          return :clear if lines.any? { |line| line =~ /You don't find anything of interest here/ }
          return :found if lines.any? { |line| line =~ /Success!/ }
          # a Failure, or no answer, goes round again
        end
      end

      # DISARM the apparatus a search showed, until it is done or there is
      # no going on.
      #
      # @param trap_room [Room] where the trap went off
      # @return [void]
      def disarm(trap_room)
        deadline = Time.now + DEADLINE
        attempts = 0

        loop do
          break unless here?(trap_room)
          break if dead? || muckled?
          break if Time.now > deadline
          break if attempts >= DISARM_ATTEMPTS

          EO.settle
          attempts += 1
          results = EO.command('disarm apparatus', DISARM_RESULT)
          break if results.any? { |line| line =~ /Success!|You want to disarm what\?/ }
        end
      end

      # Where to wait out the itchy curse when no room is set for it: the
      # nearer of the nearest town and the nearest sanctuary.
      #
      # @return [Integer, nil] a room id
      def safe_place
        distances = Room.current.dijkstra.last
        town = Room.current.find_nearest_by_tag('town')
        sanctuary = Room.current.find_nearest_by_tag('sanctuary')

        [town, sanctuary].compact.sort_by { |room| distances[room] }.first
      end

      # Wait for the rash to go, three minutes at most.
      #
      # @return [void]
      def wait_out_rash
        timeout = Time.now + 180
        loop do
          break if Time.now > timeout
          break if reget(50).any? { |line| line =~ RASH_GONE }
          sleep(1)
        end
      end
    end
  end
end
