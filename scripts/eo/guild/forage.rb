# frozen_string_literal: true

module EO
  module Guild
    # Herb tasks: where an herb grows, what it is called once picked, the
    # gathering loop, and giving the herbs to the herbalist.
    module Forage
      module_function

      # The forage_options setting: helper spells, hiding, gambits, running
      # from creatures. skip_healing says a hurt forager keeps going.
      Policy = Struct.new(:options, :skip_healing, keyword_init: true) do
        def initialize(options: [], skip_healing: false)
          super(options: Array(options).map(&:to_s), skip_healing: skip_healing)
        end

        def use?(key) = options.include?(key.to_s)
      end

      # The task names some herbs by a form that FORAGE does not.
      TASK_NAMES = {
        /ayana (weed|lichen|berry|root)/i    => 'ayana leaf',
        /ayana'al (weed|lichen|berry|root)/i => "ayana'al leaf",
      }.freeze

      # The task shortens some mushroom names; the item in the sack is the full one.
      STOW_NAMES = {
        'white mushroom'    => 'white hook mushroom',
        'trafel mushroom'   => 'black trafel mushroom',
        'withered mushroom' => 'withered black mushroom',
        'soft mushroom'     => 'soft white mushroom',
        'red mushroom'      => 'red trafel mushroom',
        'black mushroom'    => 'black hook mushroom',
        'golden mushroom'   => 'golden hook mushroom',
      }.freeze

      FOUND = /^You forage briefly and manage to find/
      # The herb cannot be found in this room now: picked clean, or the wrong
      # climate for it. Only the start of the line: what follows differs.
      NOTHING_HERE = /^As you carefully forage around you (?:can )?(?:find no (?:hint|trace)|see no evidence) of what you are looking for/
      PICKED_OVER = /^As you forage around, you notice that someone has been foraging here recently and you are unable to find anything useful\./
      GIVE_RESULT = /This looks perfect|That looks like it has been partially used up/

      # @param herb [String] as the task names it
      # @return [String] as FORAGE wants it
      def forage_name(herb)
        TASK_NAMES.each { |pattern, name| return name if herb =~ pattern }
        herb
      end

      # @param herb [String] as the task names it, in any case
      # @return [String] as the item reads in a container, in lower case
      def stow_name(herb)
        name = herb.downcase
        STOW_NAMES.fetch(name, name)
      end

      # Does a container item answer to the herb, whatever the case? Ayana
      # items are named by their part, so the herb name may only start with
      # the item's.
      #
      # @param item_name [String]
      # @param herb [String] the task's name for it
      # @return [Boolean]
      def match?(item_name, herb)
        full = stow_name(herb)
        (item_name =~ /#{Regexp.escape(full)}/i || (full.start_with?(item_name.downcase) && full =~ /ayana/)) ? true : false
      end

      # The items in +container+ that answer to the herb.
      #
      # @param container [GameObj]
      # @param herb [String]
      # @return [Array<GameObj>]
      def in_container(container, herb)
        container.contents.to_a.select { |item| match?(item.name, herb) }
      end

      # Rooms tagged with the herb, nearest first, whatever the case of the
      # herb or the tag. With a location, only rooms there: by its exact case,
      # and without regard to case when that finds none. With "nearest", the
      # ten closest within 90 steps.
      #
      # @param herb [String] as the task names it
      # @param forage_item [String] what the task's FORAGE link names (may differ)
      # @param location [String] a location name, or "nearest"
      # @param from [Room]
      # @return [Array<Integer>] room ids
      def rooms(herb, forage_item, location = 'nearest', from: Room.current)
        herb = forage_name(herb)
        herb_alt = herb.sub(/^some /i, '')
        pattern = /#{Regexp.escape(herb)}|#{Regexp.escape(herb_alt)}|#{Regexp.escape(forage_item.to_s)}/i

        low = herb.downcase
        ids = Room.list.select do |r|
          r.tags.any? do |tag|
            tag = tag.downcase
            tag.end_with?(low) || (low.start_with?(tag) && low =~ /ayana/) || low.end_with?(tag)
          end
        end.map(&:id)
        ids.select! { |id| Room[id].tags.any? { |tag| tag =~ pattern } }

        nearest = location.eql?('nearest')
        unless nearest
          where = Regexp.escape(location.strip)
          exact = ids.select { |id| Room[id].location.to_s =~ /#{where}/ }
          ids = exact.empty? ? ids.select { |id| Room[id].location.to_s =~ /#{where}/i } : exact
        end

        _previous, distance = from.dijkstra
        ids = ids.select { |id| distance[id] && (!nearest || distance[id] <= 90) }.sort_by { |id| distance[id] }
        nearest ? ids.first(10) : ids
      end

      # What the task's FORAGE link names, from BOUNTY, when it differs from
      # the herb in the text.
      #
      # @param herb [String] the fallback
      # @return [String]
      def forage_item(herb)
        lines = EO.command('bounty', /<a exist=".*?" noun="#{Char.name}"/, silent: true, quiet: true)
        line = lines.find { |l| l =~ /concoction that requires <d cmd="(.*?)">/ }
        line ? Regexp.last_match(1).sub(/^forage /, '').strip : herb
      end

      # FORAGE SENSE's last line: how many of the room's five forage slots
      # are left. Every herb in a room shares them; they come back one at a
      # time, every five to ten minutes.
      SENSE_SLOTS = [
        [/The surroundings look lush and verdant\./, 5],
        [/The surroundings look a bit browsed\./, 3],
        [/The surroundings look picked over\./, 2],
        [/The surroundings look scavenged\./, 1],
        [/someone has been foraging around here recently and you will be unable to find anything useful/, 0],
      ].freeze
      # Ranks of Survival that unlock FORAGE SENSE.
      SENSE_RANKS = 25

      # The room's forage slots left, from FORAGE SENSE; nil without the
      # Survival for it, or when the answer is not one of the five.
      #
      # @return [Integer, nil]
      def slots_left = sense.first

      # FORAGE SENSE, and the slots it says are left.
      #
      # @return [Array(Integer, Array<String>), Array(nil, Array<String>)]
      #   the slots (nil when unknown) and the answer's lines
      def sense
        return [nil, ["no FORAGE SENSE: Survival #{Skills.survival.to_i} of #{SENSE_RANKS}"]] if Skills.survival.to_i < SENSE_RANKS

        lines = EO.command('forage sense', Regexp.union(SENSE_SLOTS.map(&:first)), silent: true, quiet: true, timeout: 3)
        SENSE_SLOTS.each { |pattern, slots| return [slots, lines] if lines.any? { |line| line =~ pattern } }
        [nil, lines]
      end

      # Hurt enough to stop and heal: the hands and head FORAGE needs
      # (Lich's Injured.able_to_search?), a wound or scar past rank 1, or
      # health under 70%.
      #
      # @param policy [Policy] skip_healing says never
      # @return [Boolean]
      def hurt?(policy)
        return false if policy.skip_healing
        return true unless Lich::Gemstone::Injured.able_to_search?

        XMLData.injuries.any? { |_area, h| h['wound'] > 1 || h['scar'] > 1 } || Char.percent_health < 70
      end

      # Whether creatures here send a forager on, by the run option.
      #
      # @param policy [Policy]
      # @return [Boolean]
      def run?(policy) = policy.use?(:run) && !GameObj.targets.empty?

      # Whether this room can be foraged at all: not run from, claimed, no
      # black void.
      #
      # @param policy [Policy]
      # @return [Boolean]
      def workable?(policy)
        # GameObj.loot is nil for a room with nothing on the ground
        !run?(policy) && Claim.mine? && GameObj.loot.to_a.none? { |i| i.name =~ /black void/ }
      end

      # Before each FORAGE: the helper spells, kneeling, the yierka, 608,
      # hiding.
      #
      # @param policy [Policy]
      # @param creatures [Array<GameObj>] already calmed by 619, added to
      # @return [void]
      def settle_in(policy, creatures)
        nomagic = Map.current.tags.include?('meta:nomagic')
        Heirloom::Spells.helpers(policy, creatures) unless nomagic
        3.times do
          break if kneeling?

          fput 'kneel'
          EO.settle
        end
        yierka(policy)
        if !nomagic && policy.use?(:use_608) && Spell[608].known? && !hidden?
          Lich::Gemstone::Mana.pulse(608)
          Spell[608].cast if Spell[608].affordable?
        end
        fput 'hide' if (policy.use?(:use_gambit) || policy.use?(:hiding)) && !hidden?
      end

      # One FORAGE, and what it came to; a find is put in the sack.
      #
      # @param item [String] what to FORAGE for
      # @param sack [GameObj]
      # @param gambit [Boolean] a Rogue with the stealth put gambit
      # @return [Symbol] :found, :injured, :picked_over (the slots are gone),
      #   :not_here (the herb does not grow here or no answer), or :missed
      def forage_once(item, sack, gambit: false)
        result = EO.result("forage for #{item}", Tables::FORAGE_RESULT)
        EO.settle
        if result =~ FOUND
          stow_found(sack, gambit: gambit)
          :found
        elsif result =~ Tables::FORAGE_INJURY
          EO.settle
          Spell[114].cast if Spell[114].known? && Spell[114].affordable? && !Map.current.tags.include?('meta:nomagic')
          :injured
        elsif result =~ PICKED_OVER then :picked_over
        elsif result.nil? || result =~ NOTHING_HERE then :not_here
        else :missed
        end
      end

      # Leaving a room: stand, hands back, 213 stopped.
      #
      # @param policy [Policy]
      # @return [void]
      def leave_room(policy)
        EO.stand
        fill_hands
        Heirloom::Spells.stop_sanctuary(policy)
      end

      # Forage in each room until the sack holds enough. Returns early when
      # creatures arrive and the policy says to run. A driver with its own
      # loop calls the steps above one at a time.
      #
      # @param item [String] what to FORAGE for
      # @param count [Proc] how many are held now
      # @param needed [Integer]
      # @param rooms [Array<Integer>]
      # @param policy [Policy]
      # @param sack [GameObj] where to put what is found
      # @param gambit [Boolean] a Rogue with the stealth put gambit
      # @param hurt [Proc] called when wounded enough to stop; returns after healing
      # @return [void]
      def gather(item:, count:, needed:, rooms:, policy:, sack:, gambit: false, hurt: nil)
        creatures = []
        EO.settle
        Lich::Gemstone::Stance.change('defensive')
        rooms.each do |room|
          EO.go2(room)
          next unless workable?(policy)

          empty_hands
          loop do
            settle_in(policy, creatures)
            case forage_once(item, sack, gambit: gambit)
            when :found
              held = count.call
              Lich::Messaging.msg('info', " #{held} of #{needed} #{held > 1 ? "#{item}s" : item} foraged")
              break if held >= needed
            when :not_here then break
            when :picked_over
              break unless evoke_bounty?(policy)

              next
            end
            if hurt && hurt?(policy)
              back = Room.current.id
              hurt.call
              EO.go2(back)
            end
            break if run?(policy)
          end
          leave_room(policy)
          break if count.call >= needed
        end
        Heirloom::Spells.stop_peace(policy)
      end

      # Put what was foraged in the sack, up to five tries, by gambit while
      # hidden: a stealth put that fails reveals, so each try looks again.
      #
      # @param sack [GameObj]
      # @param gambit [Boolean] the stealth put gambit is known
      # @return [void]
      def stow_found(sack, gambit: false)
        item = [GameObj.right_hand, GameObj.left_hand].find { |i| !i.noun.nil? }
        return if item.nil?
        5.times do
          fput "#{gambit && checkhidden ? 'rgambit stealth ' : ''}put my #{item.noun} in my #{sack}"
          EO.settle
          held = [GameObj.right_hand, GameObj.left_hand].map(&:id).compact
          break if !held.include?(item.id) && sack.contents.to_a.map(&:id).include?(item.id)
        end
      end

      # Assume the yierka form for 650 when the policy wants it.
      def yierka(policy)
        return unless policy.use?(:use_650) && !Map.current.tags.include?('meta:nomagic')
        if Spell[650].known? && Spell[650].affordable? && !Spell[650].active? && !Spell[9039].active?
          multifput('prep 650', 'assume yierka')
        elsif Spell[650].active? && !Spell[9039].active? && Char.mana >= 25
          waitcastrt?
          fput 'assume yierka'
        end
      end

      # A picked-over room can be renewed by evoking 604.
      #
      # @return [Boolean] whether it was evoked
      def evoke_bounty?(policy)
        return false if Effects::Cooldowns.active?("Nature's Bounty Foraging") || Skills.slblessings < 15
        return false unless policy.use?(:use_604evoke) && Spell[604].known? && Spell[604].affordable?
        return false if Map.current.tags.include?('meta:nomagic')
        Spell[604].force_evoke
        true
      end

      # @param town [String] the task's town
      # @return [Integer, nil] the herbalist's room there
      def herbalist_room(town)
        square = Tables.town_room(town)
        square&.find_nearest(Tables.herbalist_rooms)
      end

      # @param town [String]
      # @return [Boolean] within two rooms of the herbalist, close enough to turn in on the way
      def near_herbalist?(town)
        room = herbalist_room(town) or return false
        _previous, distance = Room.current.dijkstra
        distance[room].to_i <= 2
      end

      # Give the herbs to the herbalist. A refused one (partly used, say) is
      # put away; whether the rest are still offered is the caller's: a
      # turn-in on the way stops there, the return to town goes on, or one
      # bad herb at the front of the sack would hold back all the good ones.
      #
      # @param herbs [Array<GameObj>] the items
      # @param town [String]
      # @param past_refusals [Boolean] offer the rest after one is refused
      # @return [Boolean] whether the task text changed
      def give(herbs, town, past_refusals: false)
        return false if herbs.empty?
        EO.go2(herbalist_room(town))
        EO.settle
        herbalist = NPCs.find(Tables::HERBALIST_NAMES)
        empty_hands
        before = checkbounty
        herbs.each do |h|
          before = checkbounty
          EO.result("_drag ##{h.id} right", Tables::GET_RESULT)
          res = EO.result("give ##{h.id} to ##{herbalist.id}", GIVE_RESULT)
          next if res =~ /perfect/
          EO.result("stow ##{h.id}", Tables::PUT_RESULT) if checkleft || checkright
          break unless past_refusals
        end
        fill_hands
        Taskmaster.changed?(before)
      end
    end
  end
end
