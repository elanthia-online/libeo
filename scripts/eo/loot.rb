# frozen_string_literal: true

module EO
  # Loot: telling it from what merely lies in a room, deciding whether an
  # item is wanted, and searching a dead creature.
  #
  # Commands go through the running script's helpers (EO.use). The helpers
  # this needs: command(text, pattern, silent:, quiet:) answering the lines,
  # and say(type:, text:).
  module Loot
    module_function

    # Things in a room that are no loot, by name.
    NON_LOOT_NAMES = [
      # what 335's deities leave
      'golden light',
      'jet black scimitar',
      'midnight black flames',
      'reddish haze',
      'sourceless shadow',
      'swirling blue-green pillar of water',

      # a Ranger's vines
      'bramble',
      'briar',
      'clutch of twisted branches',
      'creeper',
      'ivy',
      'smilax',
      'swallowwort',
      'tumbleweed',
      'vine',
      'widgeonweed',

      'child',
      'jagged crater',
      'massive icicle',
      'point of elemental instability',
      'rolton droppings',
      'rotting tree stump',
      'sealed fissure',
      'severed',
      'slender silvery thread',
      'slippery wooden chute',
      'small puddle',
      'vathor club'
    ].freeze

    # Things in a room that are no loot, by noun.
    NON_LOOT_NOUNS = %w[cloud cyclone door gangplank kitten maw mist muck puppy space staircase].freeze

    # What a floating disk can look like; someone's disk is "Name <noun>".
    DISK_NOUNS = /\b(?:bassinet|cassone|chest|coffer|coffin|coffret|disk|hamper|saucer|sphere|trunk|tureen)\b/

    # Every type a character can choose to loot.
    CATEGORIES = ['alchemy', 'armor', 'box', 'clothing', 'collectible', 'cursed', 'food', 'gem', 'herb', 'jewelry', 'junk', 'lockpick',
                  'lm trap', 'magic', 'reagent', 'scroll', 'skin', 'uncommon', 'valuable', 'wand', 'weapon'].freeze

    # LOOT's answers.
    SEARCH_ANSWER = /You (search|plunge|break|tentatively)|not in any condition|see well enough to search|You can only loot creatures|Geez!  It's still alive!  Not a good time for that\.|As you (?:move to )?search/
    # The answers after which there is no point in trying again.
    SEARCH_DONE = /You (search|plunge|break|tentatively)|not in any condition|see well enough to search|You can only loot creatures|Geez!  It's still alive!  Not a good time for that\./
    # A find the search left on the ground.
    AT_FEET = /^(?:<pushBold\/> \*\* (?:A glint of light catches your eye, and you notice|Among the remains, you find|Among the spoils, you find)|Among the remains, you find) an? <a exist="(?<id>[\d-]+)" noun="(?<noun>[\w-]+)">(?<name>[\w\s-]+)<\/a>.*?(?: at your feet! \*\*|! \*\*|, which falls alongside your feet\.)$/

    # Frozen bramble creatures, by noun: their find lands in the left hand.
    BRAMBLE_NOUNS = %w[tumbleweed plant shrub creeper vine bush].freeze
    # Creatures whose find lands in a hand.
    IN_HAND = /\b#{Regexp.union(BRAMBLE_NOUNS + %w[skayl glacei caedera golem elemental])}\b/

    # A list of words or patterns as one pattern matching any of them as
    # whole words.
    #
    # @param list [Array<String, Regexp>, nil]
    # @return [Regexp]
    def words(list)
      Regexp.union(
        Array(list).map do |entry|
          source = entry.is_a?(Regexp) ? entry.source : entry.to_s
          /\b(?:#{source})\b/
        end
      )
    end

    # Whether something lying in a room is no loot at all: a room feature, a
    # spell's leavings, someone's disk, plain weapons and armor, or an item
    # learned to be unlootable or to crumble.
    #
    # @param obj [GameObj]
    # @param keep [Array<String, Regexp>] names always taken for loot
    # @param heirloom [Regexp, nil] the heirloom a bounty wants, always taken for loot
    # @param unlootable [Array<String>, nil] names learned to be unlootable,
    #   nil when that list is not in use
    # @param crumbly [Array<String>] names learned to crumble
    # @return [Boolean]
    def junk?(obj, keep: [], heirloom: nil, unlootable: nil, crumbly: [])
      return false if keep.length.positive? && obj.name =~ Regexp.union(keep)
      return false if heirloom && obj.name =~ heirloom

      name_regex = Regexp.union(NON_LOOT_NAMES)
      noun_regex = Regexp.union(NON_LOOT_NOUNS)

      (obj.name =~ /\b#{name_regex}\b/i ||
        obj.name =~ /[A-Z][a-z]+ #{DISK_NOUNS}\b/ ||
        obj.noun =~ /\b#{noun_regex}\b/i ||
        obj.id.to_i.negative? ||
        (obj.type =~ /weapon|armor/i && obj.type !~ /uncommon|clothing/i) ||
        unlootable&.include?(obj.name) ||
        crumbly.include?(obj.name)) ? true : false
    end

    # Whether a piece of loot is wanted.
    #
    # @param thing [GameObj]
    # @param types [Array<String>] the types the character loots
    # @param exclude [Regexp] names never wanted
    # @param heirloom [Regexp, nil] the heirloom a bounty wants
    # @param level [Integer] the character's level
    # @return [Boolean]
    def wanted?(thing, types:, exclude:, heirloom: nil, level: Stats.level)
      return false if thing.name.match?(exclude)

      # oblivion quartz is no curse to a character of level 100
      return true if thing.name.eql?('shard of oblivion quartz') && level.eql?(100) && types.include?('gem')

      # cursed first: a cursed gem is a gem too
      return false if thing.type =~ /cursed/i && !types.include?('cursed')

      return true if thing.type =~ Regexp.union(types)
      return true if heirloom && thing.name =~ heirloom

      return false if thing.type =~ Regexp.union(CATEGORIES - types)

      true
    end

    # @param thing [GameObj] a dead creature
    # @return [Boolean] whether its find lands in a hand
    def in_hand?(thing) = thing.name =~ IN_HAND ? true : false

    # @param thing [GameObj] a dead creature
    # @return [Boolean] whether it is a frozen bramble creature
    def bramble?(thing) = BRAMBLE_NOUNS.any?(thing.noun)

    # LOOT a dead creature, up to three tries.
    #
    # @param thing [GameObj]
    # @param sigil [Boolean] cast Sigil of Determination and try again when
    #   too hurt to search
    # @param on_find [Proc, nil] given each item the search left at the
    #   character's feet, as a GameObj
    # @return [void]
    def search(thing, sigil: false, on_find: nil)
      3.times do
        waitrt?
        results = EO.command("loot ##{thing.id}", SEARCH_ANSWER, silent: false, quiet: false)
        EO.say(type: 'debug', text: "Thing: #{thing.id}-#{thing.name}, Results: #{results.first}")

        if results.any? { |line| line =~ /not in any condition/ } &&
           sigil &&
           Spell['Sigil of Determination'].affordable? &&
           !Spell['Sigil of Determination'].active?
          Spell['Sigil of Determination'].cast
          next
        end

        results.each do |line|
          next unless line =~ AT_FEET

          match = Regexp.last_match
          on_find&.call(GameObj.new(match[:id], match[:noun], match[:name]))
        end

        break if results.any? { |line| line =~ SEARCH_DONE } || thing.nil? || thing.status =~ /gone/
      end
    end
  end
end
