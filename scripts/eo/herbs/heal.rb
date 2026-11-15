# frozen_string_literal: true

module EO
  module Herbs
    # Healing with a herb: choosing one for a type from what the sack
    # holds, the spells that make herbs work better, and eating or drinking it.
    #
    # Commands go through the running script's helpers (EO.use). The helpers
    # this needs: result(text, pattern) answering one line, and wait().
    module Heal
      module_function

      # Every answer to eating or drinking a herb.
      USED = /^You (?:manage to )?take a (?:bite|drink)|You eat your|You must pick the|Why don't you leave some for others|Using your/

      # @param item [GameObj]
      # @param type [String]
      # @return [Boolean] whether the table has the item, by its name or
      #   short name, as treating that type
      def treats?(item, type)
        Table::KNOWN.any? { |h| (h[:name] =~ /#{item.name}/ || h[:short_name] =~ /#{item.name}/) && h[:type] == type }
      end

      # A herb for a type already in a hand.
      #
      # @param type [String]
      # @return [GameObj, nil]
      def in_hand(type)
        [GameObj.right_hand, GameObj.left_hand].find do |i|
          Table::KNOWN.any? { |h| h[:type] == type && (h[:name] =~ /#{i.name}/ || h[:short_name] =~ /#{i.name}/) }
        end
      end

      # The herb to use for a type, from what the sack holds: yabathilium
      # for blood when that is preferred, then something eaten or something
      # drunk as preferred, then anything.
      #
      # @param contents [Hash{Symbol => Array<GameObj>}] the sack's contents by form
      # @param type [String]
      # @param use_yaba [Boolean] prefer yabathilium for blood
      # @param use_potions [Boolean] prefer what is drunk to what is eaten
      # @return [GameObj, nil]
      def find(contents, type, use_yaba: false, use_potions: false)
        if type == 'blood' && use_yaba
          yaba = contents[:all].find { |i| i.name =~ /yabathilium/ }
          return yaba if yaba
        end

        herb = contents[use_potions ? :drinkable : :edible].find { |i| treats?(i, type) }
        return herb if herb

        contents[:all].find { |i| treats?(i, type) }
      end

      # What to pass over from now on when no herb was found for a type:
      # the areas it covers, so the next type is one that can be treated.
      #
      # @param type [String]
      # @return [Array<String>]
      def skip_for(type)
        case type
        when /head/ then %w[head neck]
        when /organ|missing eye/ then ['torso']
        when /limb/ then ['limbs']
        when /nerve/ then ['nerves']
        else [type]
        end
      end

      # Cast what makes herbs work better: Sigil of Mending, Song of Tonis
      # (1035), and the yierka's aspect (650).
      #
      # @param use_mending [Boolean]
      # @param use1035 [Boolean]
      # @param use650 [Boolean]
      # @return [void]
      def cast_spells(use_mending:, use1035:, use650:)
        if use_mending && Spell[9713].known? && Spell[9713].affordable? && !Effects::Buffs.active?('Sigil of Mending')
          waitcastrt?
          Spell[9713].cast
        end

        if Spell[1035].known? && Spell[1035].affordable? && !Effects::Buffs.active?('Song of Tonis') && use1035 && Lich::Gemstone::Injured.able_to_cast?
          waitcastrt?
          Spell[1035].cast
        end

        return unless use650 && Lich::Gemstone::Injured.able_to_cast?

        if Spell[650].known? && Spell[650].affordable? && !Spell[650].active? && !Effects::Buffs.active?('Aspect of the Yierka') && !Spell[9039].active?
          waitcastrt?
          multifput('prep 650', 'assume yierka')
        elsif Spell[650].active? && !Effects::Buffs.active?('Aspect of the Yierka') && !Spell[9039].active? && checkmana > 25
          waitcastrt?
          fput 'assume yierka'
        end
      end

      # Eat or drink a herb, and wait out the roundtime.
      #
      # @param herb [GameObj]
      # @param drinkable [Boolean] it is something drunk, as taking it out showed
      # @param no_get [Boolean] eat it where it lies, without picking it up
      # @return [Symbol] :used; :must_take (it has to be picked up);
      #   :enough (the game will give no more from here); or :no_answer
      def use(herb, drinkable: false, no_get: false)
        command = if no_get
                    "eat #{herb.noun}"
                  else
                    herb.name =~ Table::DRINKABLE || drinkable ? "drink my #{herb.noun}" : "eat my #{herb.noun}"
                  end

        result = EO.result(command, USED)
        EO.settle
        if result =~ /You must pick the/ then :must_take
        elsif result =~ /Why don't you leave some for others?/ then :enough
        elsif result.nil? then :no_answer
        else :used
        end
      end
    end
  end
end
