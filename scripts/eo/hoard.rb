# frozen_string_literal: true

module EO
  # Hoarding gems and reagents in jars: the name a jar's label and an item
  # share, whether a name is a gem or a reagent, what a stash of jars
  # holds, and shaking a jar.
  #
  # An inventory is a list of entries, each a Hash of :item (the name),
  # :count and :full; the empty jars are one entry of their own.
  #
  # Commands go through the running script's helpers (EO.use). The helpers
  # this needs: command(text, pattern, silent:, quiet:) answering the lines,
  # and say(type:, text:).
  module Hoard
    module_function

    JAR = /^(?:jar|bottle|beaker)$/
    EMPTY_JARS = '*** empty jars ***'

    # The towns LOCKER MANIFEST takes.
    MANIFEST_TOWNS = ["Wehnimer's Landing", 'Teras Isle', 'Solhaven', "River's Rest", 'Icemule Trace', 'Zul Logoth', "Ta'Illistim",
                      "Ta'Vaalor", 'Mist Harbor', 'Cysaegir', "Kraken's Fall", 'Family Vault'].freeze

    # The line each container's part of a manifest begins with.
    MANIFEST_SECTIONS = {
      /trunk/i    => 'bound in wrought iron',
      /chest/i    => 'deep chest',
      /rack/i     => 'weapon rack',
      /stand/i    => 'armor stand',
      /bin/i      => 'magical item bin',
      /wardrobe/i => 'clothing wardrobe'
    }.freeze

    PLURALS = { 'ies' => 'y', 'onyxes' => 'onyx', 'zes' => 'z', 's' => '' }.freeze

    # The plain, singular name a jar's label and a loose item have in
    # common: no article, size or "of polished", and a few names the two
    # write differently.
    #
    # @param name [String, GameObj, nil]
    # @return [String, nil] nil for no name
    def normalize(name)
      EO.say(type: 'debug', text: "name: #{name}")
      return if name.nil?

      if name.is_a?(String)
        case name
        when /essences? of (air|earth|water|fire)/
          return "essence of #{Regexp.last_match(1)}"
        when /golden seed/
          return 'tiny golden seed'
        when /motes? of essence/
          name = name.gsub(/motes?/, 'mote')
        end
      end

      name = name.full_name if name.is_a?(GameObj)
      name = name.downcase

      sizes = 'tiny|small|medium|large|blue-violet|pyrite-capped vibrant'
      articles = 'some|an? |the'
      descriptors = '(?:\\w+ )*?\\w+s? of(?: polished)?|polished'

      pattern = /^\s*(?:containing )?(?:#{articles})?\s*(?:#{sizes})?\s*(?:#{descriptors})?\s*(?:#{sizes})?\s*(.*?)\s*$/
      raise 'FIXME: normalize pattern did not match but should match anything' unless name =~ pattern

      name = Regexp.last_match(1)

      if name =~ /^(.*?)(#{PLURALS.keys.map { |x| Regexp.escape(x) }.join('|')})$/
        "#{Regexp.last_match(1)}#{PLURALS[Regexp.last_match(2)]}"
      else
        name
      end
    end

    # Whether a name is of the kind being hoarded, by Lich's type data and
    # a few names it does not have.
    #
    # @param item [String] a normalized name
    # @param type [String] 'gem' or 'alchemy'
    # @return [Boolean]
    def kind?(item, type)
      GameObj.load_data if GameObj.type_data.empty?

      obj_type = type == 'alchemy' ? 'reagent' : type

      item = item.gsub(/teeth/, 'tooth')
      noun = item.split.last
      data = GameObj.type_data[obj_type]

      if item =~ data[:exclusion]
        false
      elsif data[:name].to_s.match?(/\b#{item}\b/) || data[:noun].to_s.match?(/\b#{noun}\b/)
        true
      elsif item =~ data[:name] || noun =~ data[:noun]
        true
      elsif obj_type == 'reagent' && Room.list.any? { |r| r.tags.any? { |tag| tag.end_with?(item) || (item.start_with?(tag) && item =~ /ayana/) || item.end_with?(tag) } }
        true
      elsif obj_type == 'reagent' && item =~ /kezmonian honey beryl|faintly glimmering dust/i
        true
      elsif obj_type == 'gem' && item =~ /(?:deep blue sapphire|fiery ruby|glistening onyx|sparkling emerald) talon/i
        true
      else
        false
      end
    end

    # The entries whose name holds the filter as a phrase, whatever the case.
    #
    # @param entries [Array<Hash>]
    # @param filter [String, nil]
    # @return [Array<Hash>] all of them for no filter
    def filter(entries, filter)
      phrase = filter.to_s.downcase.split.join(' ')
      return entries if phrase.empty?

      entries.select { |entry| entry[:item].to_s.downcase.split.join(' ').include?(phrase) }
    end

    # LOOK IN the stash, so Lich has what it holds now: a locker's contents
    # are not kept up to date.
    #
    # @param stash [GameObj]
    # @return [void]
    def refresh(stash)
      EO.command("look in ##{stash.id}", /<container id='.*?' title=/, silent: true, quiet: true)
    end

    # What a jar holds, read by looking in it.
    #
    # @param jar [GameObj]
    # @param stash [GameObj, nil] the container the jar is in, for a jar not in hand
    # @return [Array(Integer, Boolean), Symbol, nil] the portions and whether
    #   it is full; :empty for a jar in hand that says so; nil when the
    #   answer said neither
    def read_jar(jar, stash: nil)
      lines = if stash
                EO.command("look in ##{jar.id} from ##{stash.id}", /^Inside .*? you see [0-9]+ portion/, silent: true, quiet: true)
              else
                EO.command("look in ##{jar.id}", /^Inside .*? you see [0-9]+ portion|^The <a exist=".*?is empty/, silent: true, quiet: true)
              end

      if lines.find { |line| line =~ /^Inside .*? you see ([0-9]+) portion/ }
        [Regexp.last_match[1].to_i, lines.any?(/It is full/)]
      elsif !stash && lines.find { |line| line =~ /^The <a exist=".*?is empty/ }
        :empty
      end
    end

    # The inventory of a stash, by looking in every labelled jar.
    #
    # @param stash [GameObj]
    # @param type [String] 'gem' or 'alchemy'
    # @yield [percent] after each jar, how far along it is
    # @return [Array<Hash>]
    def inventory(stash, type)
      inventory = []

      refresh(stash)
      labelled = stash.contents.find_all { |obj| obj.noun =~ JAR && !obj.after_name.nil? }
      empty_jars = stash.contents.count { |obj| obj.noun =~ JAR && obj.after_name.nil? }

      inventory << { item: EMPTY_JARS, count: empty_jars, full: '  -' } if empty_jars.positive?

      labelled.each_with_index do |jar, index|
        if (held = read_jar(jar, stash: stash))
          count, full = held
          item = normalize(jar.after_name).strip
          inventory << { item: item, count: count, full: full } if kind?(item, type)
        end

        yield (((index + 1).to_f / labelled.size) * 100).round(2) if block_given?
      end

      inventory
    end

    # The town LOCKER MANIFEST knows a premium locker by.
    #
    # @param cache [String] the stash container's name
    # @param city [String] the locker's town, as the map names it
    # @return [String, nil] nil when it is not a town a manifest can be had for
    def manifest_town(cache, city)
      town = 'Family Vault' if cache =~ /trunk/i
      town ||= { 'Kharam-Dzu' => 'Teras Isle', 'the Isle of Four Winds' => 'Mist Harbor' }[city] || city
      MANIFEST_TOWNS.include?(town) ? town : nil
    end

    # The inventory of a premium locker's stash, from LOCKER MANIFEST, which
    # needs no visit.
    #
    # @param town [String] from manifest_town
    # @param cache [String] the stash container's name
    # @param type [String] 'gem' or 'alchemy'
    # @return [Array<Hash>, nil] nil when the manifest has no part for the container
    def manifest_inventory(town, cache, type)
      start_from = MANIFEST_SECTIONS.find { |pattern, _line| cache =~ pattern }&.last

      lines = EO.command("locker manifest #{town}", /Thinking back, you recall the contents|Looking in front of you/, silent: true, quiet: true)

      start_index = lines.index { |line| line.include?(start_from) }
      return nil unless start_index

      end_index = lines[(start_index + 1)..].index { |line| line.strip.empty? }
      end_index = end_index.nil? ? lines.size : end_index + start_index + 1

      section = lines[(start_index + 1)...end_index]
      inventory = []

      empty_jars = section.count { |line| line.match?(/(?:jar|bottle|beaker)/) && !line.include?('containing') }
      inventory << { item: EMPTY_JARS, count: empty_jars, full: '  -' } if empty_jars.positive?

      section.each do |line|
        match = line.match(/containing\s(?<item>.*?)\s+\((?<stored>\d+)\/(?<capacity>\d+)\)(?:\s+\(.*?\))?\z/)
        next unless match

        item = normalize(match[:item]).strip
        stored = match[:stored].strip.to_i
        inventory << { item: item, count: stored, full: stored == match[:capacity].strip.to_i } if kind?(item, type)
      end

      inventory
    end

    # The jar in a stash labelled with a name.
    #
    # @param stash [GameObj]
    # @param name [String] a normalized name, taken as a pattern
    # @return [GameObj, nil]
    def jar_of(stash, name)
      stash.contents.find { |obj| obj.noun =~ JAR && normalize(obj.after_name) =~ /^#{name}$/ }
    end

    # SHAKE one item out of a jar held in a hand.
    #
    # @param jar [GameObj]
    # @return [Array(GameObj, Boolean)] what is now in a hand that is not
    #   the jar, and whether that was the last one in it
    def shake(jar)
      lines = EO.command("shake ##{jar.id}", /You give your <a exist=".*?"/)
      item = [GameObj.right_hand, GameObj.left_hand].find { |i| i.id !~ /#{jar.id}/ }
      [item, lines.any?(/That was the last/)]
    end

    # @return [GameObj, nil] a jar held in a hand
    def jar_in_hand
      [GameObj.right_hand, GameObj.left_hand].find { |i| i.noun =~ JAR }
    end
  end
end
