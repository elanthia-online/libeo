# frozen_string_literal: true

module EO
  module Herbs
    # The herb sack: a container the character carries, a Survivalist's Kit,
    # or something in the room that herbs are in, on, under or behind.
    # Opening it, reading what it holds by form, and putting herbs in and
    # taking them out.
    #
    # Commands go through the running script's helpers (EO.use). The helpers
    # this needs: result(text, pattern) answering one line, and a lines
    # helper, lines(text, pattern), answering the lines of a command sent
    # quietly.
    module Sack
      module_function

      # An OPEN answer that means this opened it, so it wants closing after.
      NEEDS_CLOSED = Regexp.union(
        /You throw back/i,
        /You open/i,
        /You pick at the knot/i,
        /You unfasten/i,
        /With a quick glance over your shoulder/i,
        /You pull the long strips of leather/i,
        /With a flick of your wrist/i,
        /Sliding the lever on the side/i,
        /You rub your hand/i,
        /Myriad spectral moths pull a cloakwing moth/
      )

      CLOSE = Regexp.union(
        /^You (?:reach over your \w+ and )?close/,
        /^That is already closed/,
        /As you push/,
        /You tie/
      )

      # Every answer to putting a herb away, bundling included.
      PUT = Regexp.union(
        /^You (?:put|(?:discreetly )?tuck|attach|toss|attempt to shield your|place|.* place|slip|wipe off the blade and sheathe|absent-mindedly drop|carefully add|find an incomplete bundle|untie your drawstring pouch)/,
        /^The .+ is already a bundle/,
        /^Your bundle would be too large if you tried to add that/,
        /^The .+ is too large to be bundled\./,
        /^As you place your .+ inside your .+, you notice another .+ inside the .+ and carefully arrange the two .+ into a neat bundle\./,
        /If you wish to continue, throw the item away again within fifteen seconds/,
        /you feel pleased with yourself at having cleaned up the surrounding area/,
        /over your shoulder/,
        /two items in that location/,
        /wear three functional items/,
        /^Your .*? won't fit in .*?\.$/,
        /You add/,
        /You find a suitable/,
        /^Your .+ is already fully stocked with (?:solid|liquid) \w+\.  You put .+ in your .+\.$/
      )

      # Every answer to taking a herb out.
      GET = Regexp.union(
        /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly|just )?(?:remove|pick up|draw|grab|reach|slip|tuck|retrieve|already have|unsheathe|detach|swap)/,
        /^Get what\?$/,
        /^Why don't you leave some for others\?$/,
        /^You need a free hand/,
        /^You already have that/,
        /You just poured yourself/,
        /You retrieve/,
        /You break off/
      )

      # The game's refusal to give more from a shared container.
      ENOUGH = /Why don't you leave some for others?/

      KIT_DOSES = %r{^(.*?)The.*?exist="(-?\d+)" noun="(.*?)">(.*?)</a> contains DOSEs (.*?)\.}
      KIT_TINCTURES = %r{^(.*?)The.*?exist="(-?\d+)" noun="(.*?)">(.*?)</a> contains TINCTUREs (.*?)\.}
      KIT_ITEM = %r{(:?) <a exist="(.*?)" noun="(.*?)">(.*?)</a> (\(\d+\))}

      # @param container [GameObj]
      # @return [Boolean] whether the character carries it
      def carried?(container)
        GameObj.inv.find { |obj| obj.id =~ /#{container.id}/ } ? true : false
      end

      # A carried container, by a word of its name.
      #
      # @param name [String]
      # @return [GameObj, nil]
      def carried(name)
        GameObj.inv.find { |obj| obj.name =~ /\b#{name}\b/i }
      end

      # Something in the room, by a word of its name.
      #
      # @param name [String]
      # @return [GameObj, nil]
      def in_room(name)
        (GameObj.room_desc.to_a + GameObj.loot.to_a).find { |obj| obj.name =~ /#{name}/i }
      end

      # Open a container unless Lich already has what is in it, and look in.
      #
      # @param sack [GameObj]
      # @yield when the OPEN is what opened it, so it wants closing after
      # @return [Symbol, nil] :locked, else nil
      def open(sack)
        return if sack.nil? || sack.empty?
        return if GameObj.containers.keys.include?(sack.id) && sack.contents.is_a?(Array)

        result = EO.lines("open ##{sack.id}", Containers::OPEN)
        yield if result.grep(NEEDS_CLOSED).any? && block_given?

        return :locked if result.grep(/It appears to be locked./).any?

        lines = EO.lines("look in ##{sack.id}", Containers::LOOK)
        return if lines.grep(/You glance|There is nothing/i).any?

        20.times do
          break if GameObj.containers.keys.include?(sack.id) && sack.contents.is_a?(Array)

          sleep 0.1
        end
        nil
      end

      # Sort what a container holds into what is drunk and what is eaten.
      # Only what Lich types as a herb counts.
      #
      # @param contents [Array<GameObj>]
      # @return [Hash{Symbol => Array<GameObj>}] :drinkable, :edible and :all
      def by_form(contents)
        items = { drinkable: [], edible: [], all: [] }
        contents.each do |h|
          next unless h.type == 'herb'

          items[h.name =~ Table::DRINKABLE ? :drinkable : :edible].push(h)
          items[:all].push(h)
        end
        items
      end

      # What a Survivalist's Kit holds: its DOSEs and TINCTUREs, which LOOK
      # lists with counts, and any loose herbs in it besides.
      #
      # @param kit [GameObj]
      # @return [Hash{Symbol => Array<GameObj>}] :drinkable, :edible and :all
      def kit_contents(kit)
        result = EO.lines("look in ##{kit.id}", %r{(In|On|Under|Behind) .*?exist="(#{kit.id})" noun="(.*?)">(.*?)</a|There is nothing}).join(' ')
        contents = { drinkable: [], edible: [], all: [] }

        { edible: KIT_DOSES, drinkable: KIT_TINCTURES }.each do |form, pattern|
          next unless result =~ pattern

          Regexp.last_match(5).scan(KIT_ITEM).each do |_what, exist, noun, name|
            contents[form].push(GameObj.new_inv(exist, noun, name, kit.id.to_s))
            contents[:all].push(GameObj.new_inv(exist, noun, name, kit.id.to_s))
          end
        end

        loose = GameObj[kit.id].contents
        unless loose.empty?
          known = Table::KNOWN.map { |item| item[:name] }.uniq
          loose.each do |h|
            next unless known.include?(h.name)

            form = h.name =~ Table::DRINKABLE ? :drinkable : :edible
            contents[form].push(h) unless contents[form].include?(h)
            contents[:all].push(h) unless contents[:all].include?(h)
          end
        end

        contents
      end

      # The herbs in, on, under or behind something in the room, read by
      # LOOK. A closed one is opened and looked in again.
      #
      # @param sack [GameObj]
      # @param preposition [String] 'in', 'on', 'under' or 'behind'
      # @yield when an OPEN is what opened it
      # @return [Array<GameObj>, Symbol] the herbs the table knows, or
      #   :locked
      def room_contents(sack, preposition, &opened)
        listing = {}

        loop do
          result = EO.lines("look #{preposition} ##{sack.id}", %r{(In|On|Under|Behind) .*?exist="(#{sack.id})" noun="(.*?)">(.*?)</a|There is nothing}).join(' ')

          case result
          when %r{Under .*?exist="(-?\d+)" noun="(.*?)">(.*?)</a>(?::| you see )(.*?)$}
            listing['under'] = Regexp.last_match(4)
            break
          when %r{Behind .*?exist="(-?\d+)" noun="(.*?)">(.*?)</a>(?::| you see )(.*?)$}
            listing['behind'] = Regexp.last_match(4)
            break
          when %r{On .*?exist="(-?\d+)" noun="(.*?)">(.*?)</a>(?::| you see )(.*?)$}
            listing['on'] = Regexp.last_match(4)
            break
          when %r{In .*?exist="(-?\d+)" noun="(.*?)">(.*?)</a>(?::| you see )(.*?)$}
            listing['in'] = Regexp.last_match(4)
            break
          when /That is closed./
            break unless preposition == 'in'
            return :locked if Sack.open(sack, &opened) == :locked
          else
            break
          end
        end

        contents = []
        # nothing was listed when the look said none of these
        listing[preposition].to_s.scan(%r{<a exist="(.*?)" noun="(.*?)">(.*?)</a>}).each do |exist, noun, name|
          contents.push(GameObj.new_inv(exist, noun, name, sack.id.to_s))
        end

        contents.select { |obj| Table::KNOWN.find { |herb| herb[:name] =~ /#{obj.name}/ } }
      end

      # Put an item in, on, under or behind a container.
      #
      # @param item_id [String]
      # @param container_id [String]
      # @param preposition [String, nil] 'in' when none is given
      # @return [String, nil] the game's answer
      def put(item_id, container_id, preposition = nil)
        preposition = 'in' if preposition.to_s.empty?
        EO.result("put ##{item_id} #{preposition} ##{container_id}", PUT)
      end

      # Take a herb out into a free hand, freeing one first.
      #
      # @param herb [GameObj]
      # @return [Boolean, Symbol, nil] true when the answer shows it is
      #   something drunk; :enough when the game will give no more from
      #   here; else nil
      def take(herb)
        free_hand

        to = GameObj.right_hand.id.nil? ? 'right' : 'left'
        result = EO.result("_drag ##{herb.id} #{to}", GET)

        if result =~ Table::DRINKABLE
          true
        elsif result =~ ENOUGH
          :enough
        end
      end

      # Make a hand free by STOW, unless one is empty on an arm that can be
      # used: the right when it is full and usable or the left arm is beyond
      # use, else the left.
      #
      # @return [void]
      def free_hand
        right_ok = [::Wounds.rightArm, ::Wounds.rightHand, ::Scars.rightArm, ::Scars.rightHand].max < 3
        left_ok = [::Wounds.leftArm, ::Wounds.leftHand, ::Scars.leftArm, ::Scars.leftHand].max < 3
        return if (GameObj.right_hand.id.nil? && right_ok) || (GameObj.left_hand.id.nil? && left_ok)

        left_gone = [::Wounds.leftArm, ::Wounds.leftHand, ::Scars.leftArm, ::Scars.leftHand].max == 3
        waitrt?
        if GameObj.right_hand.id && (right_ok || left_gone)
          free_hands(right: true)
        else
          free_hands(left: true)
        end
      end

      # STOW what the hands hold.
      #
      # @return [void]
      def free_hands(right: false, left: false, both: false)
        fput "stow #{GameObj.right_hand}" if (right || both) && checkright
        fput "stow #{GameObj.left_hand}" if (left || both) && checkleft
      end
    end
  end
end
