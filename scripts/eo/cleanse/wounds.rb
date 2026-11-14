# frozen_string_literal: true

module EO
  module Cleanse
    # Whether the character's wounds and scars allow a spell to be cast.
    module Wounds
      module_function

      # The places a wound or scar bears on casting.
      CASTING = /nsys|head|(left|right)(Eye|Arm|Hand)/

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
    end
  end
end
