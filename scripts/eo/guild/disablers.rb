# frozen_string_literal: true

module EO
  module Guild
    # Spells that stop creatures without killing them, for getting past a
    # room with someone in tow: which the character can cast now, the best
    # of them for what is in the room, and the cast.
    module Disablers
      module_function

      # A creature already in no state to attack.
      DISABLED = /dead|prone|lying down|stunned|sleeping|webbed|calm|sitting|frozen/
      # Effects that keep the character from casting.
      DEBUFFS = ['Bind', 'Corrupt Essence', 'Calm', 'Mind Jolt', 'Net', 'Silenced', 'Sleep', 'Web'].freeze

      # The disabling spells: whether each may be cast where there is
      # justice, and whether it stops one creature only. Call Wind (504)
      # takes the whole room from twenty ranks of air lore.
      #
      # @return [Array<Hash>] each with :num, :town_safe and :single_target
      def table
        [
          { :num => 135,  :town_safe => false, :single_target => false },
          { :num => 201,  :town_safe => true,  :single_target => true },
          { :num => 213,  :town_safe => true,  :single_target => false },
          { :num => 316,  :town_safe => false, :single_target => false },
          { :num => 410,  :town_safe => false, :single_target => false },
          { :num => 501,  :town_safe => true,  :single_target => true },
          { :num => 504,  :town_safe => true,  :single_target => Skills.elair >= 20 ? false : true },
          { :num => 505,  :town_safe => true,  :single_target => true },
          { :num => 519,  :town_safe => true,  :single_target => true },
          { :num => 619,  :town_safe => false, :single_target => false },
          { :num => 706,  :town_safe => true,  :single_target => true },
          { :num => 709,  :town_safe => false, :single_target => false },
          { :num => 912,  :town_safe => true,  :single_target => false },
          { :num => 1005, :town_safe => true,  :single_target => true },
          { :num => 1011, :town_safe => true,  :single_target => false },
          { :num => 1207, :town_safe => true,  :single_target => true },
          { :num => 1219, :town_safe => false, :single_target => false },
          { :num => 1608, :town_safe => false, :single_target => false },
        ]
      end

      # Whether the character is in a state to cast: not stunned or dead,
      # without the wounds that stop a cast (Lich's Injured.able_to_cast?),
      # and under none of DEBUFFS.
      #
      # @return [Boolean]
      def can_cast?
        return false if stunned? or dead?
        return false unless Lich::Gemstone::Injured.able_to_cast?
        # need effect names for "Terrified", "Unconscious", "Staggered", and whatever else I'm missing
        debuffs_prevent_cast = !(Effects::Debuffs.to_h.keys & DEBUFFS).empty?
        return false if debuffs_prevent_cast
        return true
      end

      # Ask JUSTICE STATUS, keeping its answer off the screen. Waits for
      # the answer however long it takes.
      #
      # @return [Boolean] whether there is justice here
      def justice?
        justice = nil
        action = proc { |server_string|
          if server_string =~ /^You sense that your surroundings are calm|^There is no justice/
            justice = (server_string =~ /You sense that your surroundings are calm/ ? true : false)
            nil
          else
            server_string
          end
        }
        DownstreamHook.add("#{Script.current.name}_check_justice", action)
        put 'justice status'
        until !justice.nil?
          sleep 0.01
        end
        DownstreamHook.remove("#{Script.current.name}_check_justice")
        return justice
      end

      # The spell to cast at what is in the room: of those known and
      # affordable, safe for the place and fit for the number and kind of
      # creatures, the cheapest. Against more than one creature Sanctuary
      # (213) or Song of Peace (1011) is taken at any cost.
      #
      # @param min_mana [Integer] mana to have left after the cast
      # @param custom [Integer, false] a spell to use whenever it is known
      #   and affordable
      # @param untargetable [Array<String>] names of creatures not counted
      # @param skip_can_cast [Boolean] choose without asking can_cast?
      # @return [Hash, nil] an entry of the table, or only :num for the
      #   custom spell; nil when there is none
      def best(min_mana:, custom:, untargetable:, skip_can_cast: false)
        return nil if can_cast? == false and skip_can_cast == false
        # find all eligible spells
        candidates = table.find_all { |disabler|
          spell = Spell[disabler[:num]]
          spell.known? and spell.affordable? and ((mana - spell.mana_cost) >= min_mana.to_i)
        }
        return nil if (candidates.nil? or candidates.empty?) # no justice check if no disablers
        return { :num => custom } if custom.is_a?(Integer) && Spell[custom].known? && Spell[custom].affordable?
        # filter spells that are safe in town if you're in town
        justice = justice?
        if justice
          candidates = candidates.find_all { |disabler|
            disabler[:town_safe] == true
          }
        end

        # filter out single target spells if more than 1 target
        npcs = GameObj.targets.find_all { |npc| !untargetable.include?(npc.name) and npc.status !~ DISABLED }
        if npcs.size > 1
          candidates = candidates.find_all { |i| !i[:single_target] }

          # multi target filtering section
          candidates = candidates.find_all { |i| i[:num] != 410 } if GameObj.npcs.any? { |i| i.name =~ /\b(?:glacei|wraith|elemental|cold guardian)\b/ }

          # pick the preferred sanctuary spells - regardless of cost
          preferred = candidates.find { |i| i[:num].to_s =~ /213|1011/ }
          return preferred unless preferred.nil?
        else
          name = npcs[0] ? npcs[0].name : nil
          # single target filtering section
          candidates = candidates.find_all { |i| i[:num] != 501 } if name =~ /\b(?:glacei|corpse|wraith|elemental|ghost)\b/
          candidates = candidates.find_all { |i| i[:num] != 505 } if name =~ /\b(?:glacei|elemental|wraith)\b/
          candidates = candidates.find_all { |i| i[:num] != 410 } if name =~ /\b(?:glacei|griffin|grifflet|elemental)\b/
          candidates = candidates.find_all { |i| i[:num] != 709 } if name =~ /\b(?:glacei|griffin|grifflet|elemental)\b/
          candidates = candidates.find_all { |i| i[:num] != 706 } if name =~ /\b(?:glacei|construct|elemental|brawler|protector|psionicist|fanatic)\b/
          candidates = candidates.find_all { |i| i[:num] != 201 } if name =~ /\b(?:grimswarm|construct)\b/
        end

        # order spells with least mana cost
        candidates = candidates.sort { |a, b|
          (Spell[a[:num]].mana_cost) <=> (Spell[b[:num]].mana_cost)
        }

        return candidates.first
      end

      # TARGET RANDOM, and wait for what it says.
      #
      # @return [Boolean] whether there is now a target
      def target_random
        put 'target random'
        while (line = get)
          if line =~ /Could not find a valid target\./
            return false
          elsif line =~ /You are now targeting/
            return true
          end
        end
      end

      # Cast a spell chosen by best. Song of Peace (1011) is renewed when
      # it is already up.
      #
      # @param candidate [Hash] with :num
      # @return [Boolean] whether it was Song of Peace, which is to be
      #   stopped when the work is done
      def cast(candidate)
        spell = Spell[candidate[:num]]
        if spell.num == 1011
          fput 'spell active'
          if spell.active?
            fput 'renew 1011'
          else
            spell.cast
          end
          true
        else
          spell.cast
          false
        end
      end
    end
  end
end
