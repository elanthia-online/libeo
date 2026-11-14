# frozen_string_literal: true

module EO
  module Cleanse
    # What is done to the character: disease and poison, magical debuffs, a
    # root or press, a stun, a web or bind. Each method is the cure itself;
    # whether to try it at all is the calling script's.
    #
    # Commands go through the running script's helpers (EO.use). The helpers
    # this needs: wait(), and a lines helper, lines(text, pattern), answering
    # the lines of a command sent quietly.
    module Afflictions
      module_function

      # Debuffs Retreat gets the character out of.
      GROUNDED = %w[Rooted Pressed].freeze
      # Debuffs a dispel cast on oneself removes.
      DISPELLABLE = ['Confusion', 'Vertigo', 'Sounds', 'Thought Lash', 'Mindwipe', 'Pious Trial', 'Powersink'].freeze
      # Creatures that are a part of something else: Quake (709) is not for them.
      APPENDAGE = /^(?:arm|appendage|claw|limb|pincer|tentacle)s?$|^(?:palpus|palpi)$/i

      # Cast Undisease (113) until the disease is gone or the mana is.
      #
      # @return [void]
      def cure_disease
        until !checkdisease || !Spell[113].affordable?
          Spell[113].cast
          EO.settle
        end
      end

      # Cast Unpoison (114) until the poison is gone, a Wall of Thorns'
      # too, or the mana is. The debuffs are read again after each cast
      # while thorns poison lasts, as nothing else tells when it ends.
      #
      # @return [void]
      def cure_poison
        loop do
          thorns_active = if Gem::Version.new(LICH_VERSION) >= Gem::Version.new('5.10.2')
                            Status.thorned?
                          else
                            Effects::Debuffs.to_h.keys.any? { |key| key.to_s =~ /Wall of Thorns Poison/ }
                          end

          break if (!checkpoison && !thorns_active) || !Spell[114].affordable?

          Spell[114].cast
          EO.settle

          EO.helper(:lines).call('spell active debuff', /<dialogData id='Debuffs'/) if thorns_active
        end
      end

      # Retreat from what holds the character down, once for each of
      # GROUNDED that is active while there is the stamina: stand, drop the
      # target, retreat, and take the target up again.
      #
      # @param before [Proc, nil] called before each retreat
      # @return [void]
      def retreat(before: nil)
        GROUNDED.each do |debuff|
          next unless Effects::Debuffs.active?(debuff) && Char.stamina >= 11

          before&.call
          EO.settle
          fput 'stand' until checkstanding
          EO.settle
          current_target = XMLData.current_target_id
          fput 'target clear'
          fput 'cman retreat'
          fput "target ##{current_target}"
        end
      end

      # Dispel the debuffs on the character, an open channel of the dispel
      # for each of DISPELLABLE that is active.
      #
      # @param dispel [Spell]
      # @param before [Proc, nil] called before each
      # @return [void]
      def dispel_debuffs(dispel, before: nil)
        Lich::Gemstone::Mana.pulse(dispel.num)

        DISPELLABLE.each do |debuff|
          next unless Effects::Debuffs.active?(debuff)

          before&.call
          Lich::Gemstone::Mana.pulse(dispel.num)

          fput 'stand' until checkstanding
          EO.settle
          dispel.force_incant('channel open') if dispel.affordable?
        end
      end

      # The ways out of a stun the character has ready, of those allowed.
      # The combat maneuvers are not used in the two rooms a creature has
      # swallowed the character into.
      #
      # @param allow [Hash{Symbol => Boolean}] :stunned1040, :barkskin,
      #   :beseech, :berserk, :stance1, :stance2, :flee, :hide
      # @return [Hash{Symbol => Boolean}] the same keys, true for each ready
      def stun_means(allow)
        means = Hash.new(false)
        swallowed = !(checkroom('The Belly of the Beast').nil? && checkroom('Ooze, Innards').nil?)

        if allow[:stunned1040] && Spell[1040].known?
          Lich::Gemstone::Mana.pulse(1040)
          means[:stunned1040] = Spell[1040].available?
        end

        if allow[:barkskin] && Spell[605].known? && !Effects::Cooldowns.active?('Barkskin: Commune') && !Effects::Cooldowns.active?('Barkskin') && !Spell[605].active? && Skills.slblessings >= 15
          Lich::Gemstone::Mana.pulse(605)
          means[:barkskin] = Spell[605].available?
        end

        if allow[:beseech] && Spell[1635].known?
          Lich::Gemstone::Mana.pulse(1635)
          means[:beseech] = Spell[1635].available?
        end

        unless swallowed
          means[:berserk] = allow[:berserk] && CMan.available?('Berserk')
          means[:stance1] = allow[:stance1] && CMan.available?('Stun Maneuvers', min_rank: 3)
          means[:stance2] = allow[:stance2] && CMan.available?('Stun Maneuvers', min_rank: 4)
          means[:flee] = allow[:flee] && CMan.available?('Stun Maneuvers', min_rank: 5)
          means[:hide] = allow[:hide] && CMan.available?('Stun Maneuvers', min_rank: 5) && !checkhidden
        end

        means
      end

      # Get out of a stun by the first of the means: barkskin, berserk,
      # 1040, beseech, then the stun maneuvers.
      #
      # @param means [Hash{Symbol => Boolean}] from stun_means
      # @return [void]
      def break_stun(means)
        if means[:barkskin]
          EO.settle
          fput 'commune barkskin' if stunned?
          sleep 0.1 while checkstunned
        elsif means[:berserk]
          berserk
        elsif means[:stunned1040]
          fput 'shout 1040'
        elsif means[:beseech]
          fput 'beseech'
        elsif means[:stance1]
          stun_maneuver('stance1')
        elsif means[:stance2]
          stun_maneuver('stance2')
        elsif means[:flee]
          stun_maneuver('flee')
        elsif means[:hide]
          stun_maneuver('hide')
        end
      end

      # Go berserk and wait for it to end.
      #
      # @api private
      def berserk
        Spell[9607].cast
        sleep 1
        wait_until { !Spell[9607].active? }
      end

      # A stun maneuver, standing first: a stance; fleeing until the room
      # changes, then the second stance; or hiding until hidden. Each goes on
      # only while the stun lasts, and the stun is waited out after.
      #
      # @param type [String] 'stance1', 'stance2', 'flee' or 'hide'
      # @return [void]
      def stun_maneuver(type)
        stun_stand

        case type
        when 'stance1', 'stance2'
          CMan.use('stunman', type)
        when 'flee'
          current_room = Room.current.id
          until Room.current.id != current_room || !checkstunned
            stun_stand
            CMan.use('stunman', 'flee')
            sleep 0.5
          end
          CMan.use('stunman', 'stance2')
        when 'hide'
          until checkhidden || !checkstunned
            stun_stand
            CMan.use('stunman', 'hide')
            EO.settle
          end
        end

        sleep 0.1 while checkstunned
      end

      # Stand by stun maneuver while stunned and down.
      #
      # @return [void]
      def stun_stand
        until standing? || !checkstunned
          CMan.use('stunman', 'stand')
          EO.settle
        end
      end

      # Whether there is a way out of a web or bind: 1040, berserk, beseech
      # or Escape Artist. A mana pulse is made for 1040 first.
      #
      # @param berserk [Boolean] berserk is allowed for this
      # @param beseech [Boolean] beseech (1635) is allowed
      # @return [Boolean]
      def web_escape?(berserk:, beseech:)
        Lich::Gemstone::Mana.pulse(1040) if Spell[1040].known?

        spell_1040_ready = Spell[1040].known? && Spell[1040].affordable?
        berserk_ready = berserk && CMan.available?('Berserk')
        beseech_ready = beseech && Spell[1635].known? && Spell[1635].affordable?
        escape_ready = Feat.available?('escapeartist', min_rank: 5) && Char.stamina >= 15

        spell_1040_ready || berserk_ready || beseech_ready || escape_ready ? true : false
      end

      # Get out of a web or bind by the first there is: 1040, berserk,
      # beseech, Escape Artist. Berserk is used when it can be, whether or
      # not it was allowed for web_escape?.
      #
      # @param beseech [Boolean] beseech (1635) is allowed
      # @return [void]
      def break_web(beseech:)
        if Spell[1040].known? && Spell[1040].affordable?
          fput 'shout 1040'
        elsif CMan.available?('Berserk')
          self.berserk
        elsif beseech && Spell[1635].known? && Spell[1635].affordable?
          fput 'beseech'
        elsif Feat.available?('escapeartist', min_rank: 5) && Char.stamina >= 15
          Feat.use('escapeartist')
        end
      end

      # Quiet a room with something in it to fight, by the first of the
      # spells allowed that the character has: Wall of Force (140), Mass
      # Calm (619), Quake (709), Wizard's Shield (919), Symbol of Sleep
      # (9811).
      #
      # @param use [Hash{Symbol => Boolean}] :use_140, :use_619, :use_709,
      #   :use_919, :use_9811
      # @return [void]
      def settle_room(use)
        if use[:use_140] && Spell[140].known? && !Effects::Buffs.active?('Wall of Force') && !Effects::Cooldowns.active?('Wall of Force')
          Lich::Gemstone::Mana.pulse(140)
          Spell[140].cast if Spell[140].affordable?
        elsif use[:use_619] && Spell[619].known?
          Lich::Gemstone::Mana.pulse(619)
          Spell[619].cast if Spell[619].affordable?
        elsif use[:use_709] && Spell[709].known? && !GameObj.npcs.any? { |c| c.name =~ APPENDAGE }
          Lich::Gemstone::Mana.pulse(709)
          Spell[709].cast if Spell[709].affordable?
        elsif use[:use_919] && !Effects::Buffs.active?("Wizard's Shield") && !Effects::Cooldowns.active?("Wizard's Shield")
          Lich::Gemstone::Mana.pulse(919)
          Spell[919].cast if Spell[919].affordable?
        elsif use[:use_9811] && Spell[9811].known?
          Spell[9811].cast
        end
      end
    end
  end
end
