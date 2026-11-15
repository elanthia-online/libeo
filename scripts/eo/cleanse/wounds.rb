# frozen_string_literal: true

module EO
  module Cleanse
    # Whether the character's wounds and scars allow a spell to be cast, and
    # changing stance.
    module Wounds
      module_function

      # The places a wound or scar bears on casting.
      CASTING = /nsys|head|(left|right)(Eye|Arm|Hand)/

      STANCES = { 0 => 'offensive', 20 => 'advanced', 40 => 'forward', 60 => 'neutral', 80 => 'guarded', 100 => 'defensive' }.freeze

      # Whether the injuries allow casting as they are. Rank 3 anywhere that
      # bears on casting stops it, as does rank 2 to the head or nerves, or
      # an arm and its hand adding to more than 1 in wounds or in scars.
      #
      # @param injuries [Hash] XMLData.injuries
      # @return [Array(Boolean, Boolean)] whether casting is possible, and
      #   whether Sigil of Determination could help when it is not: it
      #   cannot get past rank 3
      def allow_cast?(injuries = XMLData.injuries)
        able = true
        sigil_could_help = true
        right_scar = right_wound = left_scar = left_wound = 0

        injuries.each do |area, h|
          next unless area =~ CASTING
          next unless h['scar'].positive? || h['wound'].positive?

          if h['scar'] > 2 || h['wound'] > 2
            sigil_could_help = false
            able = false
            break
          elsif area =~ /nsys|head/ && (h['scar'] > 1 || h['wound'] > 1)
            able = false
            break
          elsif area =~ /left(Arm|Hand)/
            left_scar += h['scar']
            left_wound += h['wound']
            if left_scar > 1 || left_wound > 1
              able = false
              break
            end
          elsif area =~ /right(Arm|Hand)/
            right_scar += h['scar']
            right_wound += h['wound']
            if right_scar > 1 || right_wound > 1
              able = false
              break
            end
          end
        end

        [able, sigil_could_help]
      end

      # Whether the injuries allow casting under Sigil of Determination:
      # nothing at rank 3, and no arm and its hand adding to more than 2.
      #
      # @param injuries [Hash] XMLData.injuries
      # @return [Boolean]
      def allow_cast_with_sigil?(injuries = XMLData.injuries)
        able = true
        right_scar = right_wound = left_scar = left_wound = 0

        injuries.each do |area, h|
          next unless area =~ CASTING

          if h['scar'] > 2 || h['wound'] > 2
            able = false
          elsif area =~ /left(Arm|Hand)/
            left_scar += h['scar']
            left_wound += h['wound']
            if left_scar > 2 || left_wound > 2
              able = false
              break
            end
          elsif area =~ /right(Arm|Hand)/
            right_scar += h['scar']
            right_wound += h['wound']
            if right_scar > 2 || right_wound > 2
              able = false
              break
            end
          end
        end

        able
      end

      # Change stance to a percentage. Nothing is done in a Frenzy or when
      # dead, when already there, or for the defensive when already guarded
      # or better.
      #
      # @param new_stance [Integer] 0 to 100; a value that is not one of
      #   the six named stances needs Stance Perfection, else it is defensive
      # @return [void]
      def stance(new_stance)
        return if Effects::Debuffs.active?('Frenzy') || dead?
        return if Char.percent_stance == new_stance
        return if new_stance == 100 && Char.percent_stance >= 80

        cmd = if CMan.available?('Stance Perfection') && !STANCES.key?(new_stance)
                "cman stance #{new_stance}"
              elsif STANCES[new_stance]
                "stance #{STANCES[new_stance]}"
              else
                'stance defensive'
              end

        while Char.percent_stance != new_stance
          res = dothistimeout(cmd, 2, /You are now|You move into|Roundtime|wait|Your rage causes you/i)
          # only an answer with a wait in it is tried again
          break unless res =~ /Roundtime: (\d+)|wait (\d+)/i

          sleep((Regexp.last_match(1) || Regexp.last_match(2)).strip.to_f - 1)
          sleep 0.5
        end
      end
    end
  end
end
