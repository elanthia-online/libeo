# frozen_string_literal: true

module EO
  module Cleanse
    # Getting a lost weapon back: keeping the room quiet meanwhile, the
    # spirit servant, a bonded weapon's own return, RECOVER ITEM, prying a
    # weapon out of webbing, a weapon floated out of the hand, and the
    # Sanctum creature that swallows one.
    #
    # Commands and walks go through the running script's helpers (EO.use).
    # The helpers this needs: command(text, pattern) answering the lines,
    # result(text) answering the first line back, wait(), go(room),
    # say(type, text), and a lines helper, lines(text, pattern), answering
    # the lines of a command sent quietly.
    module Recovery
      module_function

      SEARCHES = 10
      PRIES = 10

      # Every answer RECOVER ITEM gives.
      RECOVER_ANSWERS = /<dialogData|You spy|You continue to intently search the area|In order to recover something|You find nothing recoverable|You're not in any condition to be searching around/

      # The Sanctum's vat, where an infected wound is cleaned.
      VAT_UID = 4_216_054

      # Cast Sanctuary (213) and Song of Peace (1011), those allowed and
      # known, to keep the room quiet for the search.
      #
      # @param use_213 [Boolean]
      # @param use_1011 [Boolean]
      # @return [Array(Boolean, Boolean)] whether each is now to be stopped after
      def calm(use_213:, use_1011:)
        stop_213 = stop_1011 = false

        if Spell[213].known? && use_213
          Cleanse.mana_pulse(213)
          Spell[213].cast if Spell[213].affordable?
          stop_213 = true
        end

        if Spell[1011].known? && use_1011
          Cleanse.mana_pulse(1011)
          Spell[1011].cast if Spell[1011].affordable?
          stop_1011 = true
        end

        [stop_213, stop_1011]
      end

      # Stop the spells calm cast.
      #
      # @param stops [Array(Boolean, Boolean)] from calm
      # @return [void]
      def stop_calm(stops)
        fput 'stop 213' if stops[0]
        fput 'stop 1011' if stops[1]
      end

      # Have a spirit servant fetch the weapon, when Spirit Servant (218) is
      # up. Sanctuary is stopped after, if SENSE shows one over the room.
      #
      # @return [Boolean] whether the servant went for it
      def servant
        return false unless Spell[218].active?

        15.times do
          break if GameObj.npcs.find { |npc| npc.noun =~ /spirit/i }

          sleep(0.1)
        end

        line = dothistimeout 'tell servant recover', 5, /flickers for a moment and manifests|has no personal recollection/
        return false unless line =~ /flickers for a moment and manifests/

        lines = EO.helper(:lines).call('sense', /You open your soul to the lesser/)
        fput 'stop 213' if lines.any? { |l| l =~ /An obvious presence of peace saturates the area and a feeling of safety overwhelms you/ }
        true
      end

      # Wait up to ten seconds for a bonded weapon to come back of itself,
      # for a character with full weapon bonding or Bonded Weapon (1625).
      #
      # @param known_ids [Array<String>] what the hands held at the loss
      # @param item [String] the noun lost
      # @return [Boolean] whether it is back
      def await_bonded(known_ids, item)
        return false unless Feat.weapon_bonding == 5 || Spell[1625].known?

        wait_time = Time.now + 10
        EO.settle until Disarms.recovered?(known_ids, item) || wait_time < Time.now
        Disarms.recovered?(known_ids, item)
      end

      # RECOVER ITEM in the room the weapon was lost in, up to ten times,
      # with the hands empty, walking back and kneeling before each. The
      # list of disarms is kept as the search goes: the weapon found, an
      # earlier one found in its place, or the room found empty.
      #
      # @param item [String] the noun lost
      # @param known_ids [Array<String>] what the hands held at the loss
      # @param room_id [Integer, nil] where it was lost
      # @param disarm_id [String, nil] its entry in the list
      # @return [Integer] how many times the hands were emptied, for filling
      #   them again
      def search(item:, known_ids:, room_id:, disarm_id:)
        hand_fills = 1
        empty_hands

        search_count = 0
        until search_count.eql?(SEARCHES)
          EO.go2(room_id)

          dothistimeout('kneel', 2, /You kneel|You are already/i) until kneeling?

          EO.settle

          lines = EO.command('recover item', RECOVER_ANSWERS)

          found = Disarms.spied_item(lines)
          if found && Disarms.same_item?(found, item)
            Disarms.remove(disarm_id)
            break
          elsif found
            EO.say('yellow', " Recovered #{found} while looking for #{item}. Still searching.")
            Disarms.remove_found(found, room_id)
          elsif Disarms.recovered?(known_ids, item)
            EO.say('yellow', " No recovery message seen, but hand state changed - treating #{item} as recovered.")
            Disarms.remove(disarm_id)
            break
          end

          if lines.grep(/You're not in any condition to be searching around/).any?
            EO.say('yellow', " Unable to search. #{item} is in room #{room_id}. Use #{$lich_char}#{Script.current.name} disarmrecover to try again.")
            break
          end

          if lines.grep(/You find nothing recoverable/).any? && Room.current.id == room_id
            EO.say('yellow', " Nothing to recover in room #{room_id}. No longer tracking disarms there.")
            Disarms.remove_room(room_id, disarm_id)
            break
          end

          if lines.grep(/In order to recover something/).any?
            empty_hands
            hand_fills += 1
          end

          search_count += 1
        end

        EO.settle
        hand_fills
      end

      # Stand, and fill the hands as often as they were emptied, the earliest
      # emptying last so everything goes back where it was.
      #
      # @param hand_fills [Integer]
      # @return [void]
      def restore_hands(hand_fills)
        fput 'stand' until standing?
        EO.settle
        $fill_hands_actions.push(*$fill_hands_actions.pop(hand_fills).reverse) if hand_fills > 1
        hand_fills.times { fill_hands }
        ReadyList.check(silent: true, quiet: true) unless ReadyList.valid?
      end

      # PRY a weapon out of webbing, up to ten times.
      #
      # @param noun [String] the weapon's noun
      # @return [Boolean] whether it came free, or there was nothing to pry
      def pry(noun)
        pry_count = 0
        until pry_count.eql?(PRIES)
          lines = EO.command("pry my #{noun}", /^Pry what|^You try to pry your|^You pry your.*free from the webbing/)
          return true if lines.any? { |l| l =~ /You pry your|Pry what/i }

          pry_count += 1
        end
        false
      end

      # Get back a weapon floated out of the hand: dispel what holds it, or
      # with no dispel just GET it, until it is in hand or a GLANCE shows it.
      #
      # @param known_ids [Array<String>] what the hands held at the loss
      # @param item [String] the noun lost
      # @param dispel [Spell, nil]
      # @return [void]
      def float_back(known_ids, item, dispel)
        until Disarms.recovered?(known_ids, item)
          if dispel.nil?
            fput "get #{item}"
          else
            Cleanse.mana_pulse(dispel.num)
            dispel.cast("at #{item}") if dispel.affordable?
          end

          lines = EO.helper(:lines).call('glance', /You glance/)
          break if lines.any? { |l| l =~ /#{item}/ }

          EO.settle
        end
        EO.settle
        ReadyList.check(silent: true, quiet: true) unless ReadyList.valid?
      end

      # CLENCH the weapon back out of the Sanctum creature that took it,
      # until it is grabbed or the creature is gone.
      #
      # @param creature [String]
      # @return [void]
      def clench(creature)
        loop do
          result = EO.result("clench #{creature}")
          EO.settle
          break if result =~ /You reach up and grab|I could not find what you were referring to./
        end
      end
    end
  end
end
