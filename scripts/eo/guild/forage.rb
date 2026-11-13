# frozen_string_literal: true

module EO
  module Guild
    # Foraging a herb for the herbalist: where it grows, the herb by the
    # name FORAGE and the map want, the spells and the kneeling before a
    # try, the try itself and what its answer means, putting the find away,
    # and handing the herbs over.
    #
    # The options are a character's forage options: a list of names such as
    # "use_213", "hiding" and "run".
    #
    # Commands go through the running script's helpers (EO.use). The helpers
    # this needs: command(text, pattern, silent:, quiet:) answering the
    # lines, result(text, pattern) answering one line, and wait().
    module Forage
      module_function

      # A try that found the herb.
      FOUND = /^You forage briefly and manage to find/
      # A try in a room where the herb is not to be had: it does not grow
      # here, or there is no trace of it now.
      NOT_HERE = /^As you carefully forage around you (?:can find no (?:hint|trace)|see no evidence) of what you are looking for(?: right now, though you are fairly certain this is where it can be found)?\.(?:  You briefly wonder if it could even thrive in this place\.)?/
      # A try in a room someone has just foraged out.
      PICKED_OVER = /^As you forage around, you notice that someone has been foraging here recently and you are unable to find anything useful\./
      # What the herbalist says of a herb handed over.
      GIVEN = /This looks perfect|That looks like it has been partially used up/
      # A task that wants a herb, and the herb.
      CONCOCTION = /The.*is working on a concoction that requires (?:a|an|some) (.*) found/
      # SENSE's line for a sanctuary over the room.
      SANCTUARY = /An obvious presence of peace saturates the area and a feeling of safety overwhelms you/

      # The mushrooms a task names shortly, by the name they carry.
      MUSHROOMS = {
        'white mushroom'    => 'white hook mushroom',
        'trafel mushroom'   => 'black trafel mushroom',
        'withered mushroom' => 'withered black mushroom',
        'soft mushroom'     => 'soft white mushroom',
        'red mushroom'      => 'red trafel mushroom',
        'black mushroom'    => 'black hook mushroom'
      }.freeze

      # The rooms a herb can be foraged in, nearest first. Asked for the
      # nearest, they are those within ninety steps, ten at most; asked for
      # a place, every room of it that can be reached.
      #
      # @param herb [String] the herb as the task names it
      # @param herb_fix [String] the herb as FORAGE takes it
      # @param location [String] a place's name, or "nearest"
      # @return [Array<Integer>] room ids
      def rooms(herb, herb_fix, location)
        herb = case herb
               when /ayana (weed|lichen|berry|root)/
                 'ayana leaf'
               when /ayana'al (weed|lichen|berry|root)/
                 "ayana'al leaf"
               else
                 herb
               end

        herb_alt = herb.gsub(/^some /, '')
        herb_pattern = /#{Regexp.escape(herb)}|#{Regexp.escape(herb_alt)}|#{Regexp.escape(herb_fix)}/

        location_list = Room.list.select do |r|
          r.tags.any? { |tag| tag.end_with?(herb) || (herb.start_with?(tag) && herb =~ /ayana/) || herb.end_with?(tag) }
        end.map(&:id)

        location_list.select! { |room_id| Room[room_id].tags.any? { |tag| tag =~ herb_pattern } }

        unless location.eql?('nearest')
          location_pattern = /#{Regexp.escape(location.strip)}/
          location_list.select! { |room_id| Room[room_id].location.to_s =~ location_pattern }
        end

        _previous, shortest_distances = Room.current.dijkstra

        location_list = location_list.select do |room_id|
          distance = shortest_distances[room_id]
          distance && (!location.eql?('nearest') || distance <= 90)
        end
        location_list = location_list.sort_by { |room_id| shortest_distances[room_id] }

        location.eql?('nearest') ? location_list.first(10) : location_list
      end

      # The herbs of a kind in the default STOW container.
      #
      # @param herb [String]
      # @return [Array<GameObj>]
      def held(herb)
        herb = MUSHROOMS.fetch(herb, herb)
        StowList.stow_list[:default].contents.find_all { |item| item.name =~ /#{herb}/ || (herb.start_with?(item.name) && (herb =~ /ayana/)) }
      end

      # What to FORAGE for, from the link BOUNTY gives the task's herb.
      #
      # @return [String, nil] nil when BOUNTY shows no such link
      def linked_item
        lines = EO.command('bounty', /<a exist=".*?" noun="#{Char.name}"/, silent: true, quiet: true)
        link = Regexp.last_match(1) if lines.any? { |l| l =~ /concoction that requires <d cmd="(.*?)">/ }
        link&.gsub(/^forage /, '')&.strip
      end

      # @return [Boolean] whether SENSE shows a sanctuary over the room
      def sanctuary?
        EO.command('sense', /You open your soul to the lesser/, silent: true, quiet: true).any? { |l| l =~ SANCTUARY }
      end

      # @return [Boolean] whether SPELL ACTIVE shows Song of Peace
      def song_of_peace?
        EO.command('spell active', /<dialogData id='Active Spells'/, silent: true, quiet: true).grep(/Song of Peace/).any?
      end

      # Cast a spell that is known and can be afforded.
      #
      # @api private
      def cast(num) = (Spell[num].cast if Spell[num].known? && Spell[num].affordable?)

      # The spells cast before a try, those the options allow: a sanctuary
      # and a song to keep the room quiet, and what helps the foraging.
      #
      # @param options [Array<String>]
      # @param creatures [Array<GameObj>] what Mass Calm (619) has been cast
      #   on already; added to
      # @return [void]
      def spells(options, creatures)
        cast(213) if Stats.prof =~ /Cleric|Empath/i && options.include?('use_213') && !sanctuary?
        cast(1011) if options.include?('use_1011') && !song_of_peace?
        cast(709) if options.include?('use_709') && !GameObj.targets.any? { |c| c.name =~ /arm/ } && !GameObj.targets.empty?

        cast(604) if !Effects::Spells.active?("Nature's Bounty") && options.include?('use_604')
        cast(506) if !Effects::Buffs.active?('Celerity') && !Effects::Cooldowns.active?('Celerity') && options.include?('use_506')
        cast(919) if !Effects::Buffs.active?("Wizard's Shield") && !Effects::Cooldowns.active?("Wizard's Shield") && options.include?('use_919')
        cast(140) if !Effects::Buffs.active?('Wall of Force') && !Effects::Cooldowns.active?('Wall of Force') && options.include?('use_140')
        cast(1035) if !Effects::Buffs.active?('Song of Tonis') && options.include?('use_1035')
        cast(9704) if !Effects::Buffs.active?('Sigil of Resolve') && options.include?('use_resolve')

        return unless !GameObj.targets.empty? && options.include?('use_619')

        targets = GameObj.targets.reject { |w| creatures.any? { |c| c.id == w.id } }
        cast(619) if targets.length.positive? && !Map.current.tags.include?('meta:nomagic')
        creatures.concat(targets)
        sleep 0.5
        waitcastrt?
      end

      # Kneel.
      #
      # @return [void]
      def kneel
        until kneeling?
          fput 'kneel'
          EO.settle
        end
      end

      # The yierka's aspect (650), Self Control's light (608) and hiding,
      # those the options allow, after kneeling and before the try.
      #
      # @param options [Array<String>]
      # @param pulse [Proc] given 608, makes a mana pulse when it cannot be afforded
      # @return [void]
      def ready(options, pulse:)
        magic = !Map.current.tags.include?('meta:nomagic')

        if options.include?('use_650') && magic
          if Spell[650].known? && Spell[650].affordable? && !Spell[650].active? && !Spell[9039].active?
            multifput('prep 650', 'assume yierka')
          elsif Spell[650].active? && !Spell[9039].active? && Char.mana >= 25
            waitcastrt?
            fput 'assume yierka'
          end
        end

        if magic && options.include?('use_608') && Spell[608].known? && !hidden?
          pulse.call(608)
          Spell[608].cast if Spell[608].affordable?
        end

        fput 'hide' if (options.include?('use_gambit') || options.include?('hiding')) && !hidden?
      end

      # FORAGE once, and wait out the roundtime.
      #
      # @param item [String] what to forage for
      # @return [String, nil] the game's answer
      def try(item)
        result = EO.result("forage for #{item}", Tables::FORAGE_RESULT)
        EO.settle
        result
      end

      # Put what was foraged in the default STOW container, up to five
      # tries, by a Rogue's stealth gambit while hidden.
      #
      # @param gambits [Boolean] the gambit is available
      # @return [void]
      def stow_found(gambits:)
        item = [GameObj.right_hand, GameObj.left_hand].find { |i| !i.noun.nil? }
        sack = StowList.stow_list[:default]

        5.times do
          if checkhidden && gambits
            fput "rgambit stealth put my #{item.noun} in my #{sack}"
          else
            fput "put my #{item.noun} in my #{sack}"
          end

          EO.settle
          break if ![GameObj.right_hand, GameObj.left_hand].map(&:id).compact.include?(item.id) && sack.contents.to_a.map(&:id).include?(item.id)
        end
      end

      # Whether a room someone foraged out can be made to yield again by
      # evoking Nature's Bounty (604).
      #
      # @param options [Array<String>]
      # @return [Boolean]
      def evoke?(options)
        !(Effects::Cooldowns.active?("Nature's Bounty Foraging") || Skills.slblessings < 15 || !Spell[604].affordable? || !Spell[604].known? || !options.include?('use_604evoke') || Map.current.tags.include?('meta:nomagic'))
      end

      # @return [Boolean] whether the character is hurt enough to go and be healed
      def hurt?
        XMLData.injuries.any? { |_a, h| h['wound'] > 1 || h['scar'] > 1 } || Char.percent_health < 70
      end

      # Stand, fill the hands, and stop a sanctuary the foraging cast.
      #
      # @param options [Array<String>]
      # @return [void]
      def leave(options)
        fput 'stand' until standing?
        fill_hands
        fput 'stop 213' if Stats.prof =~ /Cleric|Empath/i && options.include?('use_213') && sanctuary?
      end

      # Stop a Song of Peace (1011) the options allowed, if it is up.
      #
      # @param options [Array<String>]
      # @return [void]
      def stop_song(options)
        fput 'stop 1011' if options.include?('use_1011') && song_of_peace?
      end

      # Hand herbs to the herbalist one by one. One that is not perfect is
      # stowed again.
      #
      # @param herbs [Array<GameObj>]
      # @param to [String] the herbalist, as GIVE is to name them
      # @param past_refusals [Boolean] go on to the rest after one is refused
      # @return [String] the task's text before the last herb was offered
      def give(herbs, to:, past_refusals:)
        original = checkbounty
        herbs.each do |h|
          original = checkbounty

          EO.result("_drag ##{h.id} right", Tables::GET_RESULT)
          res = EO.result("give ##{h.id} to #{to}", GIVEN)
          next unless res !~ /perfect/

          EO.result("stow ##{h.id}", Tables::PUT_RESULT) if checkleft || checkright
          break unless past_refusals
        end
        original
      end
    end
  end
end
