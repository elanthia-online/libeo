# frozen_string_literal: true

require 'securerandom'

module EO
  module Cleanse
    # Weapons knocked from the hand: knowing one is back, and the list of
    # those not yet got back, which is kept across deaths and restarts in
    # UserVars.last_disarm so RECOVER ITEM can be gone back for.
    #
    # An entry of the list is a Hash of :id, :item (the noun), :room and
    # :title (where it was lost) and :at (when, in epoch seconds).
    module Disarms
      module_function

      # The game's own recovery list holds this many and drops the oldest.
      MAX = 20

      # The list is added to as the game's lines are read and taken from by
      # the script's own loop, so both hold this around their change. Kept
      # across runs: a second copy of the script may be holding it.
      LOCK ||= Mutex.new

      # Whether a hand holds something that was not there when the weapon
      # was lost, and of the noun lost when one is given. A weapon that
      # comes back often has a new id, so the ids held at the loss are what
      # is known; the noun keeps another item dragged into a hand since from
      # passing for it.
      #
      # @param known_ids [Array<String>] what the hands held at the loss
      # @param expected_noun [String, nil]
      # @return [Boolean]
      def recovered?(known_ids, expected_noun = nil)
        [GameObj.right_hand, GameObj.left_hand].any? do |hand|
          next false if hand.name == 'Empty' || known_ids.include?(hand.id)

          expected_noun.nil? || hand.noun.to_s.casecmp?(expected_noun.to_s)
        end
      end

      # @return [Array<String>] the ids the hands hold now
      def held_ids
        [GameObj.right_hand.id, GameObj.left_hand.id].reject { |id| id.nil? || id.to_s.empty? }
      end

      # The disarms not yet recovered, oldest first. A value that is not a
      # list, as an older version kept, reads as none.
      #
      # @return [Array<Hash>]
      def list
        saved = UserVars.last_disarm
        saved.is_a?(Array) ? saved : []
      end

      # @param id [String]
      # @return [Boolean]
      def tracked?(id)
        list.any? { |entry| entry[:id] == id }
      end

      # Add a disarm in the current room. This runs where the game's lines
      # are read and must not raise.
      #
      # @param noun [String] what was lost
      # @return [String] the new entry's id
      def add(noun)
        room = Room.current
        entry = { id: SecureRandom.hex(4), item: noun, room: room.id, title: Array(room.title).first.to_s, at: Time.now.to_i }
        LOCK.synchronize do
          UserVars.last_disarm = (list + [entry]).last(MAX)
        end
        entry[:id]
      end

      # @param id [String]
      # @return [void]
      def remove(id)
        LOCK.synchronize do
          UserVars.last_disarm = list.reject { |entry| entry[:id] == id }
        end
      end

      # Remove a disarm and every other saved for its room: the game has
      # said nothing is there to recover. Unmapped rooms all save no room
      # id, which says nothing of one another.
      #
      # @param room_id [Integer, nil]
      # @param disarm_id [String]
      # @return [void]
      def remove_room(room_id, disarm_id)
        LOCK.synchronize do
          UserVars.last_disarm = list.reject { |entry| entry[:id] == disarm_id || (!room_id.nil? && entry[:room] == room_id) }
        end
      end

      # Remove the latest disarm in a room that matches what a search
      # turned up in place of the one looked for.
      #
      # @param found [String] what was picked up
      # @param room_id [Integer, nil]
      # @return [void]
      def remove_found(found, room_id)
        entry = list.reverse.find { |e| e[:room] == room_id && same_item?(found, e[:item]) }
        remove(entry[:id]) unless entry.nil?
      end

      # What RECOVER ITEM's answer says was picked up.
      #
      # @param lines [Array<String>]
      # @return [String, nil] the noun when the line carries XML, else its
      #   plain text; nil when nothing was picked up
      def spied_item(lines)
        line = lines.find { |l| l =~ /You spy .+ and recover it!/ }
        return nil if line.nil?

        line[/You spy .*?noun="([^"]+)"/, 1] || line.gsub(/<[^>]+>/, '')[/You spy (.+?) and recover it!/, 1]
      end

      # @param found [String] what was picked up
      # @param noun [String] what was lost
      # @return [Boolean] whether the one names the other
      def same_item?(found, noun)
        found.to_s.match?(/\b#{Regexp.escape(noun.to_s)}\b/i)
      end
    end
  end
end
