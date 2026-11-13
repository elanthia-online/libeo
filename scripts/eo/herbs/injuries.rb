# frozen_string_literal: true

module EO
  module Herbs
    # What needs healing: the type of herb the character's own wounds call
    # for next, what another's wounds call for from how the game describes
    # them, and whether the character's wounds allow a spell.
    module Injuries
      module_function

      AREAS = %w[head neck torso limbs nerves].freeze
      # The areas in the order looked at when only what stops casting, or
      # shooting, is treated.
      FIGHTING_AREAS = %w[limbs head nerves torso].freeze

      # How LOOK describes an escort's wounds, and the herbs each takes: a
      # major wound takes its herb and then the minor one, the worst twice.
      ESCORT = {
        /severe head trauma and bleeding from the ears/                        => ['major head wound', 'major head wound', 'minor head wound'],
        /minor lacerations about the head and a possible mild concussion/      => ['major head wound', 'minor head wound'],
        /snapped bones and serious bleeding from the neck/                     => ['major head wound', 'major head wound', 'minor head wound'],
        /moderate bleeding from (?:his|her) neck/                              => ['major head wound', 'minor head wound'],
        /deep gashes and serious bleeding from (?:his|her) chest/              => ['major organ wound', 'major organ wound', 'minor organ wound'],
        /deep lacerations across (?:his|her) chest/                            => ['major organ wound', 'minor organ wound'],
        /deep gashes and serious bleeding from (?:his|her) abdomen/            => ['major organ wound', 'major organ wound', 'minor organ wound'],
        /deep lacerations across (?:his|her) abdomen/                          => ['major organ wound', 'minor organ wound'],
        /deep gashes and serious bleeding from (?:his|her) back/               => ['major organ wound', 'major organ wound', 'minor organ wound'],
        /deep lacerations across (?:his|her) back/                             => ['major organ wound', 'minor organ wound'],
        /a blinded (right|left) eye/                                           => ['major organ wound', 'major organ wound', 'minor organ wound'],
        /a swollen (right|left) eye/                                           => ['major organ wound', 'minor organ wound'],
        /a completely severed (right|left) leg|arm|hand/                       => ['major limb wound', 'major limb wound', 'minor limb wound'],
        /a fractured and bleeding (right|left) leg|arm|hand/                   => ['major limb wound', 'minor limb wound'],
        /a case of uncontrollable convulsions|a case of sporadic convulsions/  => ['major nerve wound', 'minor nerve wound'],
        /minor bruises about the head/                                         => ['minor head wound'],
        /minor bruises on (?:his|her) neck/                                    => ['minor head wound'],
        /minor cuts and bruises on (?:his|her) chest/                          => ['minor organ wound'],
        /minor cuts and bruises on (?:his|her) abdomen/                        => ['minor organ wound'],
        /minor cuts and bruises on (?:his|her) back/                           => ['minor organ wound'],
        /a bruised (right|left) eye/                                           => ['minor organ wound'],
        /some minor cuts and bruises on (?:his|her) (right|left) leg|arm|hand/ => ['minor limb wound'],
        /a strange case of muscle twitching/                                   => ['minor nerve wound']
      }.freeze

      # The type of herb the character's condition calls for next: blood
      # when under half health, then poison and disease, wounds before
      # scars and major before minor, and blood again when anything is
      # missing from health.
      #
      # @param skip [Array<String>] types and areas to pass over
      # @param skip_scars [Boolean] leave minor scars
      # @param spellcast_only [Boolean] treat only what stops casting
      # @param ranged_only [Boolean] treat only what stops shooting
      # @return [String, nil] nil when nothing is called for
      def next_type(skip: [], skip_scars: false, spellcast_only: false, ranged_only: false)
        areas = Table::AREAS
        herb_type = nil
        herb_type = 'blood' if Char.percent_health < 50 && !skip.include?('blood')
        herb_type = 'poison' if herb_type.nil? && checkpoison && !skip.include?('poison')
        herb_type = 'disease' if herb_type.nil? && checkdisease && !skip.include?('disease')
        unless spellcast_only || ranged_only
          unless herb_type
            (AREAS - skip).each do |area|
              if ::Wounds.send(area) > 1
                herb_type = "major #{areas[area]} wound"
                break
              end
            end
          end
          unless herb_type
            (AREAS - skip).each do |area|
              if ::Wounds.send(area) == 1
                herb_type = "minor #{areas[area]} wound"
                break
              end
            end
          end
          herb_type = 'severed limb' if herb_type.nil? && ::Scars.limbs == 3 && !skip.include?('limbs')
          herb_type = 'missing eye' if herb_type.nil? && (::Scars.reye == 3 || ::Scars.leye == 3) && !skip.include?('torso')
          unless herb_type
            (AREAS - skip).each do |area|
              if ::Scars.send(area) > 1
                herb_type = "major #{areas[area]} scar"
                break
              end
            end
          end
          unless herb_type
            (AREAS - skip).each do |area|
              if ::Scars.send(area) == 1 && !skip_scars
                herb_type = "minor #{areas[area]} scar"
                break
              end
            end
          end
        end
        if spellcast_only || ranged_only
          unless herb_type
            (FIGHTING_AREAS - skip).each do |area|
              worst = fighting_wound(area, spellcast_only)
              next if worst.nil?

              if worst > 1
                herb_type = "major #{areas[area]} wound"
                break
              elsif worst == 1
                herb_type = "minor #{areas[area]} wound"
                break
              end
            end
          end
          herb_type = 'severed limb' if herb_type.nil? && [::Scars.rightHand, ::Scars.rightArm, ::Scars.leftHand, ::Scars.rightHand].max == 3 && !skip.include?('limbs')
          herb_type = 'missing eye' if spellcast_only && herb_type.nil? && [::Scars.rightEye, ::Scars.leftEye].max == 3 && !skip.include?('torso')
          unless herb_type
            (FIGHTING_AREAS - skip).each do |area|
              worst = fighting_scar(area, spellcast_only)
              next if worst.nil?

              if worst > 1
                herb_type = "major #{areas[area]} scar"
                break
              end
            end
          end
        end
        herb_type = 'blood' if herb_type.nil? && (Char.health + 7) < Char.max_health && !skip.include?('blood')
        herb_type
      end

      # The worst wound in an area that bears on fighting: the limbs are the
      # arms and hands; the head, the eyes (under 'torso') and the nerves
      # count only for casting.
      #
      # @api private
      # @return [Integer, nil] nil for an area that does not count
      def fighting_wound(area, spellcast_only)
        if spellcast_only && area == 'head' then ::Wounds.head
        elsif spellcast_only && area == 'torso' then [::Wounds.leftEye, ::Wounds.rightEye].max
        elsif spellcast_only && area == 'nerves' then ::Wounds.nsys
        elsif area == 'limbs' then [::Wounds.leftArm, ::Wounds.leftHand, ::Wounds.rightArm, ::Wounds.rightHand].max
        end
      end

      # The same of scars.
      #
      # @api private
      def fighting_scar(area, spellcast_only)
        if spellcast_only && area == 'head' then ::Scars.head
        elsif spellcast_only && area == 'torso' then [::Scars.leftEye, ::Scars.rightEye].max
        elsif spellcast_only && area == 'nerves' then ::Scars.nsys
        elsif area == 'limbs' then [::Scars.leftArm, ::Scars.leftHand, ::Scars.rightArm, ::Scars.rightHand].max
        end
      end

      # What a dead character needs, from the lines of an APPRAISE: the
      # bleeding wounds; with +full+, the other wounds too, and when there
      # are none of either, the scars.
      #
      # @param lines [Array<String>]
      # @param full [Boolean]
      # @return [Array<String>] the types
      def appraise(lines, full: false)
        needs = []
        seen = ->(pattern) { lines.any? { |l| l =~ pattern } }

        needs.push('major head wound') if seen.call(/minor lacerations about the head|bleeding from the head|moderate bleeding from (?:his|her) neck|severe head trauma and bleeding from the ears|snapped bones and serious bleeding from the neck/)
        needs.push('major organ wound') if seen.call(/deep lacerations|deep gashes and serious bleeding/)
        needs.push('major limb wound') if seen.call(/a completely severed|a fractured and bleeding/)

        return needs unless full

        needs.push('major organ wound') if seen.call(/a (blinded|swollen) (right|left) eye/)
        needs.push('major nerve wound') if seen.call(/a case of (uncontrollable|sporadic) convulsions/)
        needs.push('minor head wound') if seen.call(/minor bruises about the head|minor bruises on (?:his|her) neck/)
        needs.push('minor organ wound') if seen.call(/minor cuts and bruises on (?:his|her) (chest|abdomen|back)|a bruised (right|left) eye/)
        needs.push('minor limb wound') if seen.call(/some minor cuts and bruises on (?:his|her) (right|left)/)
        needs.push('minor nerve wound') if seen.call(/a strange case of muscle twitching/)
        return needs unless needs.empty?

        needs.push('major head scar') if seen.call(/several facial scars|old mutilation wounds about (?:his|her) head|some old neck wounds|terrible scars from some serious neck injury/)
        needs.push('major nerve scar') if seen.call(/constant muscle spasms|a very difficult time with muscle control/)
        needs.push('major organ scar') if seen.call(/several painful-looking scars across|terrible, permanent mutilation of|severe bruises and swelling around/)
        needs.push('missing eye') if seen.call(/a missing (right|left) eye/)
        needs.push('major limb scar') if seen.call(/a mangled (right|left) (leg|arm|hand)/)
        needs.push('severed limb') if seen.call(/a missing (right|left) (leg|arm|hand)/)

        needs.push('minor head scar') if seen.call(/a scar across (?:his|her) (face|neck)/)
        needs.push('minor nerve scar') if seen.call(/developed slurred speech/)
        needs.push('minor organ scar') if seen.call(/an old battle scar across (?:his|her) (chest|abdominal area|back)|a black-and-blue (right|left) eye/)
        needs.push('minor limb scar') if seen.call(/old battle scars on (?:his|her) (right|left) (leg|arm|hand)/)

        needs
      end

      # What an escort needs, from the line LOOK gives of them.
      #
      # @param look [String]
      # @return [Array<String>] the types, in the order to hand them over
      def escort(look)
        ESCORT.each_with_object([]) { |(pattern, types), needs| needs.concat(types) if look =~ pattern }
      end

      # The character's condition, type by type.
      #
      # @return [Hash{String => Boolean}]
      def status
        w = ::Wounds
        s = ::Scars
        {
          'poison'            => checkpoison,
          'disease'           => checkdisease,
          'blood'             => (Char.health + 7) < Char.max_health,
          'minor head wound'  => [w.head, w.neck].include?(1),
          'major head wound'  => [w.head, w.neck].max > 1,
          'minor head scar'   => [s.head, s.neck].include?(1),
          'major head scar'   => [s.head, s.neck].max > 1,
          'minor nerve wound' => w.nerves == 1,
          'major nerve wound' => w.nerves > 1,
          'minor nerve scar'  => s.nerves == 1 && w.nerves.zero?,
          'major nerve scar'  => s.nerves > 1 && w.nerves.zero?,
          'minor organ wound' => [w.chest, w.torso, w.back].include?(1),
          'major organ wound' => [w.chest, w.torso, w.back].max > 1,
          'minor organ scar'  => [s.chest, s.torso, s.back].include?(1),
          'major organ scar'  => [s.chest, s.torso, s.back].max > 1,
          'missing eye'       => [s.reye, s.leye].max > 2,
          'minor limb wound'  => [w.rhand, w.rarm, w.rleg, w.lhand, w.larm, w.lleg].include?(1),
          'major limb wound'  => [w.rhand, w.rarm, w.rleg, w.lhand, w.larm, w.lleg].max > 1,
          'minor limb scar'   => [s.rhand, s.rarm, s.rleg, s.lhand, s.larm, s.lleg].include?(1),
          'major limb scar'   => [s.rhand, s.rarm, s.rleg, s.lhand, s.larm, s.lleg].include?(2),
          'severed limb'      => [s.rhand, s.rarm, s.rleg, s.lhand, s.larm, s.lleg].include?(3),
          'raisedead'         => checkdead,
          'lifekeep'          => checkdead
        }
      end

      # Whether the character's wounds and scars allow a spell: nothing at
      # rank 3 where it bears on casting, nothing past rank 1 to the head or
      # nerves, and no arm and its hand adding to more than 1.
      #
      # @param injuries [Hash] XMLData.injuries
      # @return [Boolean]
      def able_to_cast?(injuries = XMLData.injuries)
        right_scar = right_wound = left_scar = left_wound = 0

        injuries.each do |area, h|
          next unless area =~ /nsys|head|(left|right)(Eye|Arm|Hand)/
          next unless h['scar'].positive? || h['wound'].positive?

          return false if h['scar'] > 2 || h['wound'] > 2
          return false if area =~ /nsys|head/ && (h['scar'] > 1 || h['wound'] > 1)

          if area =~ /left(Arm|Hand)/
            left_scar += h['scar']
            left_wound += h['wound']
            return false if left_scar > 1 || left_wound > 1
          elsif area =~ /right(Arm|Hand)/
            right_scar += h['scar']
            right_wound += h['wound']
            return false if right_scar > 1 || right_wound > 1
          end
        end

        true
      end
    end
  end
end
