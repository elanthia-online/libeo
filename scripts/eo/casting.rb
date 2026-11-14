# frozen_string_literal: true

module EO
  # Casting spells on oneself and others: how many times one cast can
  # multicast, one cast and what its answer means, having the mana or the
  # stamina for it (making mana by a society's power when short), another
  # character's active spells, and manna bread.
  module Casting
    module_function

    # A cast the room will not allow: a sanctuary, or a place closed to
    # spells of war.
    REFUSED_HERE = /^Be at peace my child, there is no need for spells of war in here\.$|Spells of War cannot be cast/
    HINDERED = /^\[Spell Hindrance for/
    # The Council of Light's sign of recognition, as the character sees it.
    RECOGNITION = /^You (?:touch|scratch|rub|tap|point to) your (?:right|left) (?:eyebrow|nostril|earlobe|shoulder|cheek) with your (?:right|left) (?:pinky|forefinger|thumb|index finger)/
    # A line of SPELL ACTIVE <name>: the spell and its time left.
    ACTIVE_SPELL = /\s+([A-z0-9\s'()-]+) \.* (([0-9]+):([0-9]+):([0-9]+)|Indefinite)$/

    # Stands for "no argument" where nil is itself an argument.
    NONE = Object.new.freeze

    # How a character goes about having mana. reserve: mana never spent.
    # source: :wracking (Sign of Wracking, Council of Light), :power (Sigil
    # of Power, Guardians of Sunfist), :voln (Symbol of Mana), or nil to
    # wait for it. bail: give up when it would mean waiting.
    # wander_to_wrack: walk to where nobody is watching before wracking.
    Resources = Struct.new(:reserve, :source, :bail, :wander_to_wrack, keyword_init: true)

    # How many times a spell can be cast at once, by the mana control the
    # character's profession uses for the spell's circle.
    #
    # @param spell [Spell]
    # @return [Integer]
    def max_multicast(spell)
      ranks = 0
      if Stats.prof == 'Wizard'
        ranks = Skills.emc
      elsif Stats.prof =~ /^Cleric$|^Ranger$|^Paladin$/
        ranks = Skills.smc
      elsif Stats.prof =~ /^Empath$|^Monk$|^Bard$/
        if [1, 2].include?(spell.circle.to_i)
          ranks = Skills.smc + (Skills.mmc / 2)
        elsif spell.circle.to_i == 11
          ranks = [Skills.mmc, Skills.smc].max + ([Skills.mmc, Skills.smc].min / 2)
        elsif spell.circle.to_i == 12
          ranks = Skills.mmc + (Skills.smc / 2)
        elsif spell.circle.to_i == 4
          ranks = Skills.emc + (Skills.mmc / 2)
        end
      elsif Stats.prof =~ /^Sorcerer$|^Warrior$|^Rogue$/
        if spell.circle.to_i == 4
          ranks = Skills.emc + (Skills.smc / 2)
        elsif spell.circle.to_i == 1
          ranks = Skills.smc + (Skills.emc / 2)
        elsif spell.circle.to_i == 7
          ranks = [Skills.emc, Skills.smc].max + ([Skills.emc, Skills.smc].min / 2)
        end
      end
      (ranks / 25) + 1
    end

    # Cast a spell once, at a target or at oneself.
    #
    # @param spell [Spell]
    # @param target [String, nil] a name, or nil for oneself
    # @param multicast [Integer]
    # @param argument [Object] for a cast at oneself, what the spell is cast
    #   with in place of a multicast count (a sonic item's name); nil counts
    #   as given
    # @return [Symbol] :success, :refused_here, :bad_target, or :hindered
    #   (spell hindrance stopped it; the mana is spent)
    def cast(spell, target: nil, multicast: 1, argument: NONE)
      result = if target.nil?
                 if !argument.equal?(NONE) then spell.cast(argument)
                 elsif multicast > 1 then spell.cast(multicast.to_s)
                 else spell.cast
                 end
               elsif multicast > 1 then spell.cast("at #{target} #{multicast}")
               else
                 spell.cast("at #{target}")
               end

      if result.to_s =~ REFUSED_HERE then :refused_here
      elsif result.to_s == 'Cast at what?' then :bad_target
      elsif result.to_s =~ HINDERED then :hindered
      else :success
      end
    end

    # @return [Boolean] mana enough for +spell+ times +n+ with the reserve kept
    def mana_for?(spell, n, cost)
      spell.affordable?(multicast: n) && (Char.mana >= cost)
    end

    # See that +spell+ times +n+ can be cast, making mana the way the
    # resources say or waiting for it. A prepared spell is released before
    # a wait.
    #
    # @param spell [Spell]
    # @param n [Integer]
    # @param resources [Resources]
    # @return [Symbol] :ready; :bail (it would mean waiting and the
    #   resources say not to; "waiting..." has been said); or :no_favor
    #   (Symbol of Mana failed for want of favor, and no more mana was made)
    def ready(spell, n, resources)
      cost = spell.mana_cost(multicast: n) + resources.reserve
      return :ready if spell.affordable?(multicast: n) && (spell.mana_cost == 0 || Char.mana >= cost)
      return :ready unless spell.mana_cost > 0

      case resources.source
      when :wracking then wrack(spell, n, cost, resources)
      when :power then sigil_of_power(spell, n, cost, resources)
      when :voln then symbol_of_mana(spell, n, cost, resources)
      else
        fput 'release' unless checkprep == 'None'
        echo 'waiting for mana...'
        return :bail if resources.bail

        wait_until { spell.affordable?(multicast: n) && (spell.mana_cost == 0 || Char.mana >= cost) }
        :ready
      end
    end

    # See that a character who casts from stamina has it for +spell+ times +n+.
    #
    # @return [Symbol] :ready or :bail
    def ready_stamina(spell, n, resources)
      enough = -> { spell.affordable?(multicast: n) && (spell.mana_cost == 0 || Char.stamina >= (spell.mana_cost(multicast: n) * 2) + resources.reserve) }
      return :ready if enough.call

      echo 'waiting for stamina...'
      return :bail if resources.bail

      wait_until { enough.call }
      :ready
    end

    # Make mana with Sign of Wracking. It is cast where nobody who is not
    # of the Council can see: hidden or invisible, alone, or among those who
    # answer the sign of recognition; else, when the resources allow it,
    # after walking up to twenty rooms to find such a place, and back. With
    # nowhere to cast it unseen, the mana is waited for.
    #
    # @api private
    def wrack(spell, n, cost, resources)
      sign_of_wracking = Spell[9918]
      punishment = Spell[9012]

      until mana_for?(spell, n, cost)
        waitrt?
        waitcastrt?
        if sign_of_wracking.affordable? && !punishment.active?
          if (invisible? || hidden? || !checkpcs || safe_to_wrack?) && !Room.current.tags.include?('no-magic')
            sign_of_wracking.cast if sign_of_wracking.affordable? && !punishment.active?
          else
            unseen = false
            if resources.wander_to_wrack
              visited = []
              start_room = Room.current

              20.times do
                break if (unseen = safe_to_wrack? && !Room.current.tags.include?('no-magic'))

                wander_step(visited)
              end

              sign_of_wracking.cast if unseen && sign_of_wracking.affordable? && !punishment.active?

              Script.run('go2', "#{start_room.id} --disable-confirm", { quiet: true }) unless start_room.id == Room.current.id
            end

            unless unseen
              echo 'waiting for mana: nowhere to wrack unseen...'
              return :bail if resources.bail

              wait_until { mana_for?(spell, n, cost) }
            end
          end
        else
          fput 'release' unless checkprep == 'None'
          echo 'waiting for mana or spirit...'
          return :bail if resources.bail

          wait_until { mana_for?(spell, n, cost) || sign_of_wracking.affordable? }
        end
      end
      :ready
    end

    # One step to a neighbouring room not yet visited, else to the one
    # visited longest ago.
    #
    # @param visited [Array<String>] room ids, the latest last; added to
    # @return [void]
    def wander_step(visited)
      room = Room.current
      next_room = Wander.next_room(room, visited, [])
      visited.delete(next_room)
      visited.push(next_room)
      way = room.wayto[next_room]
      if way.class == String
        move(way)
      else
        way.call
      end
    end

    # Whether everyone here answers the sign of recognition.
    #
    # @return [Boolean]
    def safe_to_wrack?
      lines = Lich::Util.issue_command('sign of recognition', RECOGNITION, usexml: true, silent: true, quiet: true)
      acknowledgers = lines.filter_map { |line| line[/noun="(.*?)">.*?acknowledges your sign/, 1] }
      !(checkpcs - acknowledgers).count.positive?
    end

    # Make mana with Sigil of Power.
    #
    # @api private
    def sigil_of_power(spell, n, cost, resources)
      sigil = Spell[9718]
      until mana_for?(spell, n, cost)
        if sigil.affordable?
          sigil.cast
          sleep 0.2
        else
          fput 'release' unless checkprep == 'None'
          echo 'waiting for mana...'
          return :bail if resources.bail

          wait_until { mana_for?(spell, n, cost) || sigil.affordable? }
        end
      end
      :ready
    end

    # Make mana with Symbol of Mana, between its cooldowns.
    #
    # @api private
    def symbol_of_mana(spell, n, cost, resources)
      until mana_for?(spell, n, cost)
        waitrt?
        waitcastrt?
        if !Effects::Cooldowns.active?('Symbol of Mana')
          result = Spell[9813].cast
          return :no_favor if result =~ /^You strain to perform the symbol/

          sleep 0.2
        else
          fput 'release' unless checkprep == 'None'
          echo 'waiting for mana or mana cooldown...'
          return :bail if resources.bail

          wait_until { mana_for?(spell, n, cost) || !Effects::Cooldowns.active?('Symbol of Mana') }
        end
      end
      :ready
    end

    # Another character's active spells, from SPELL ACTIVE <name>.
    #
    # @param target [String]
    # @return [Hash{String => Object}] each spell's number to the minutes it
    #   has left (599.0 for one that does not end), and 'sharing' true; only
    #   'sharing' false for a character who does not share
    def active_on(target)
      res = Lich::Util.quiet_command_xml("spell active #{target}", /currently has the following active effects|has spell sharing disabled\./)
      return { 'sharing' => false } if res.any?(/has spell sharing disabled/)

      target_info = {}
      res.each do |line|
        next unless line =~ ACTIVE_SPELL

        spell_name = Regexp.last_match(1)
        spell_time = if Regexp.last_match(2) == 'Indefinite'
                       599.0
                     else
                       (Regexp.last_match(3).to_i * 60) + Regexp.last_match(4).to_i + (Regexp.last_match(5).to_i / 60.0)
                     end
        # the names SPELL ACTIVE gives that the spell list has otherwise
        if spell_name == 'Raise Dead Recovery'
          spell_name = 'Raise Dead Cooldown'
        elsif spell_name =~ /Mage Armor - /
          spell_name = 'Mage Armor'
        elsif spell_name =~ /Cloak of Shadows - /
          spell_name = 'Cloak of Shadows'
        end
        if (spell = Spell.list.find { |s| s.name == spell_name.strip || s.num.to_s == spell_name.strip })
          target_info[spell.num.to_s] = spell_time
        elsif $infomon_debug
          echo "no spell matches #{spell_name}"
        end
      end
      target_info['sharing'] = true
      target_info
    end

    # Whatever new item lands in a hand after a cast, given two seconds:
    # the bread of Manna (203), under any name it has been given.
    #
    # @param before [Array<String, nil>] the ids in the hands before the cast
    # @return [GameObj, nil]
    def new_in_hand(before)
      bread = nil
      20.times do
        break if (bread = [GameObj.right_hand, GameObj.left_hand].find { |obj| obj.id && !before.include?(obj.id) })
        sleep 0.1
      end
      bread
    end

    # Eat the bread, up to three gobbles while it is in hand, and wait up
    # to two seconds for Manna to show.
    #
    # @param bread [GameObj, nil]
    # @return [void]
    def gobble(bread)
      if bread
        3.times do
          break unless [GameObj.right_hand, GameObj.left_hand].map(&:id).include?(bread.id)
          fput "gobble ##{bread.id}"
          sleep 0.2
        end
      end

      20.times do
        break if Effects::Spells.time_left('Manna').positive?
        sleep 0.1
      end
    end
  end
end
