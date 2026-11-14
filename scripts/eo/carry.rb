# frozen_string_literal: true

require 'time'
require 'zlib'

module EO
  # What the character can carry before encumbrance, and what it carries:
  # the wiki's formula over Lich's stats, skills and active spells, the
  # inventory feed's weights, and one correction per character learned from
  # the encumbrance bands the game reports (steps of 10% to 50, then 65, 80
  # and 100).
  #
  # Capacity = trunc2((STR - 20) / 200) * body + body / 200, with STR the
  # enhanced stat plus 2 per point of Strength bonus from active spells
  # (509, 606); plus Physical Fitness bonus / 10, Porter ranks * 2, the
  # SimuCoin encumbrance reduction (100), and non-standard armor. What the
  # formula misses (the feed's whole-pound weights, anything unlisted) is the
  # correction. Encumbrance % = (carried - capacity) / body weight.
  module Carry
    module_function

    SILVER_LBS = 1 / 160.0
    # A gem the feed rounds down to 0 lbs: 100 gems weigh 10 lbs.
    GEM_LBS = 0.1
    SIMU_REDUCTION = 100
    PORTER_LBS = 2
    # Spells that raise the Strength bonus, each bonus point worth 2 STR.
    STR_SPELLS = { 509 => 15, 606 => 10 }.freeze
    # Race base weight, body weight factor and encumbrance factor (wiki: Encumbrance).
    RACES = {
      'Burghal Gnome' => [40.0, 0.40, 0.50], 'Halfling' => [45 + (1 / 3.0), 0.4533, 0.50],
      'Forest Gnome' => [47 + (2 / 3.0), 0.4767, 0.60], 'Aelotoi' => [67 + (2 / 3.0), 0.6767, 0.75],
      'Elf' => [70.0, 0.70, 0.78], 'Erithian' => [72 + (1 / 3.0), 0.7233, 0.85],
      'Sylvankind' => [72 + (1 / 3.0), 0.7233, 0.81], 'Dark Elf' => [77 + (2 / 3.0), 0.7767, 0.84],
      'Dwarf' => [77 + (2 / 3.0), 0.7767, 0.80], 'Half-Elf' => [82 + (1 / 3.0), 0.8233, 0.92],
      'Human' => [90.0, 0.90, 1.00], 'Half-Krolvin' => [100.0, 1.00, 1.10], 'Giantman' => [120.0, 1.20, 1.33]
    }.freeze
    SIMU = /Encumbrance Reduction\s+Until (.+?)\s*$/
    SIMU_END = /SimuCoin upgrades|durations are as follows|You have no/
    # Seconds before SIMU DUR is asked again of a character without the reduction.
    SIMU_RECHECK = 24 * 60 * 60
    # The values the game's encumbrance bar takes, each the top of its band;
    # 100 is Extreme and Overloaded both, so it has no top.
    BANDS = [0, 10, 20, 30, 40, 50, 65, 80, 100].freeze

    # --- the formula ------------------------------------------------------

    # Body weight from the race and the base (not enhanced) STR and CON,
    # each taken even.
    #
    # @return [Float, nil] nil for a race not in the table
    def body_weight(race: Stats.race, str: Stats.base_str[0], con: Stats.base_con[0])
      base, factor, = RACES[race.to_s]
      return nil unless base

      even = ->(stat) { stat.to_i - (stat.to_i % 2) }
      [base + ((even.call(str) + even.call(con)) * factor), base * 3].min
    end

    # The STR the formula uses: the enhanced stat (enhancives, Assume Lion)
    # plus 2 per point of Strength bonus from active spells.
    #
    # @return [Integer]
    def effective_str(enhanced: Stats.enhanced_str[0], spell_bonus: spell_str_bonus)
      enhanced.to_i + (2 * spell_bonus.to_i)
    end

    # @return [Integer] Strength bonus from the active spells in STR_SPELLS
    def spell_str_bonus = STR_SPELLS.sum { |num, bonus| Spell[num]&.active? ? bonus : 0 }

    # The formula's capacity before anything outside the stats.
    #
    # @param str [Integer] effective STR
    # @param body [Float]
    # @return [Float]
    def base_capacity(str, body) = ((((str - 20) / 200.0) * 100).floor / 100.0 * body) + (body / 200.0)

    # Physical Fitness, Porter and the SimuCoin reduction.
    #
    # @return [Float]
    def extras(pf_bonus: Skills.to_bonus(Skills.physical_fitness), porter: Lich::Gemstone::Ascension['porter'].to_i,
               simu: simu_reduction?)
      (pf_bonus.to_i / 10.0) + (porter * PORTER_LBS) + (simu ? SIMU_REDUCTION : 0)
    end

    # --- the SimuCoin reduction ---------------------------------------------

    # Whether the SimuCoin encumbrance reduction is active, read from SIMU
    # DUR once and kept in the profile until it runs out. A character without
    # one (none bought, or expired) is asked again a day later, not every time.
    #
    # @return [Boolean]
    def simu_reduction?(now: Time.now)
      # kept as epoch seconds: a profile is loaded without Time
      until_at, checked = state.values_at(:simu_until, :simu_checked)
      return true if until_at.to_i > now.to_i

      if checked.nil? || checked.to_i + SIMU_RECHECK <= now.to_i || checked.to_i < until_at.to_i
        read = read_simu_until
        return false if read.nil?

        until_at = read.to_i
        remember(simu_until: until_at, simu_checked: now.to_i)
      end
      until_at.to_i > now.to_i
    end

    # @return [Time, Integer, nil] when the reduction ends, 0 without one
    #   (none, or expired), nil when SIMU DUR gave no answer
    # @api private
    def read_simu_until
      lines = EO.command('simu dur', SIMU_END, silent: true, quiet: true)
      return nil if lines.empty?

      line = lines.find { |l| l =~ SIMU }
      line ? Time.parse(Regexp.last_match(1).sub(/\s[A-Z]{2,4}\s/, ' ')) : 0
    rescue StandardError
      nil
    end

    # --- what is carried ----------------------------------------------------

    # Pounds carried, as the game counts them: the feed's worn and held items
    # (worn armor left out: armor_adjustment has what it weighs past its
    # standard; a gem the feed shows as 0 at 0.1), plus silver.
    #
    # @param snapshot [Lich::Common::Inventory::Snapshot]
    # @param silver [Integer]
    # @return [Float]
    def carried(snapshot, silver: Lich::Gemstone::Currency.silver.to_i)
      items = snapshot.worn + [snapshot.right_hand, snapshot.left_hand].compact
      items.sum { |item| weight(item) } + (silver * SILVER_LBS)
    end

    # An item and what it holds. A container's load is the game's own
    # figure when the feed gives one; a locked box's weight already holds
    # its contents.
    #
    # @api private
    def weight(item, top: true)
      own = item.weight.to_i.to_f
      return 0.0 if own.negative?

      # worn armor's own weight is armor_adjustment's, whatever it weighs
      own = 0.0 if top && armor_stats(item)
      own = GEM_LBS if own.zero? && !top && item.type.to_s =~ /\bgem\b/
      inner = item.in_encum ? item.in_encum.to_f : item.contents.sum { |c| weight(c, top: false) }
      own + inner
    end

    # Armor lighter than standard gives capacity back, heavier takes it;
    # carried leaves worn armor out, so this is all it counts for.
    #
    # @param snapshot [Lich::Common::Inventory::Snapshot]
    # @return [Float]
    def armor_adjustment(snapshot, race: Stats.race)
      factor = RACES.dig(race.to_s, 2) || 1.0
      snapshot.worn.sum do |item|
        stats = armor_stats(item)
        stats && stats[:base_weight] ? (stats[:base_weight] - item.weight.to_i) * factor : 0
      end
    end

    # The armor a worn item is: what the game said when identify_armor asked
    # (only what is worn over the chest is armor), else what its name says
    # (named_armor).
    #
    # @param item [Lich::Common::Inventory::Item]
    # @return [Hash, nil] base_weight: the sub-group's standard weight, nil
    #   when it is not known (taken as standard then); nil when the item is
    #   not worn armor
    # @api private
    def armor_stats(item)
      return nil unless item.relation == 'worn' && item.noun

      known = state[:armor]
      return named_armor(item) if known.nil?

      known.key?(item.id.to_s) ? { base_weight: known[item.id.to_s] } : nil
    end

    WEARING = /You are currently wearing/
    # INVENTORY LOCATION's heading for the armor; a shirt or tunic that is
    # clothing is listed under "Slipped into, on your chest:".
    ARMOR_PLACE = /\AOver your chest:/
    PLACE = /\A\S.*:\s*\z/
    INSPECTED = /You carefully inspect/
    INSPECT_ARMOR = /conclude that it is ([a-z ]+?) armor that covers ([^.]+)\./

    # Find the worn armor by asking the game: the feed says what is worn but
    # not where, and robes altered to a tunic sit beside a tunic that is only
    # clothing. INVENTORY LOCATION lists armor over the chest and clothing
    # slipped into it; the armor's sub-group is its name's when that is one
    # weight, else INSPECT's (the armor group and what it covers). Asked
    # again only when what is worn changes; kept in the profile by item id.
    #
    # @param snapshot [Lich::Common::Inventory::Snapshot]
    # @return [void]
    def identify_armor(snapshot)
      seen = Zlib.crc32(snapshot.worn.map { |item| item.id.to_s }.sort.join(','))
      return if state[:armor] && state[:armor_seen] == seen

      ids = worn_armor_ids
      return if ids.nil?

      settled = true
      known = ids.to_h do |id|
        item = snapshot.worn.find { |worn| worn.id.to_s == id }
        weight = item && named_armor(item)&.dig(:base_weight)
        if item && weight.nil?
          answer = inspect_armor(item)
          settled = false if answer.nil?
          weight = answer || nil
        end
        [id, weight]
      end
      # an INSPECT that went unanswered is asked again next time
      remember(armor: known, armor_seen: settled ? seen : nil)
    end

    # @return [Array<String>, nil] ids of what INVENTORY LOCATION lists over
    #   the chest, nil without an answer
    # @api private
    def worn_armor_ids
      lines = EO.command('inventory location', WEARING, silent: true, quiet: true)
      return nil unless lines.any? { |line| line =~ WEARING }

      armor = false
      lines.each_with_object([]) do |line, ids|
        text = line.to_s.rstrip
        armor = text.match?(ARMOR_PLACE) if text.match?(PLACE)
        ids.concat(text.scan(/exist="(\d+)"/).flatten) if armor
      end
    rescue StandardError
      nil
    end

    # @return [Integer, false, nil] the standard weight of the armor INSPECT
    #   says the item is, false when it is not armor, nil without an answer
    # @api private
    def inspect_armor(item)
      lines = EO.command("inspect ##{item.id}", INSPECTED, silent: true, quiet: true)
      return nil unless lines.any? { |line| line =~ INSPECTED }
      return false unless lines.join(' ') =~ INSPECT_ARMOR

      inspected_weight(Regexp.last_match(1), Regexp.last_match(2)) || false
    rescue StandardError
      nil
    end

    # The standard weight of an armor group at a coverage, as INSPECT words
    # them: the group picks four sub-groups, the coverage the one among them
    # (torso only, with arms, with legs, with the head). Cloth is robes when
    # it covers everything and normal clothing, which is not armor, otherwise.
    #
    # @param group [String] cloth, leather, scale, chain or plate
    # @param covers [String] "the torso and arms"
    # @return [Integer, nil] nil for normal clothing or a group not known
    # @api private
    def inspected_weight(group, covers)
      row = case group
            when /cloth/ then 0
            when /scale|rigid/ then 2
            when /leather/ then 1
            when /chain/ then 3
            when /plate/ then 4
            end
      return nil unless row

      step = if covers =~ /head/ then 3
             elsif covers =~ /legs/ then 2
             elsif covers =~ /arms/ then 1
             else 0
             end
      asg = row.zero? ? (step == 3 ? 2 : 1) : (row * 4) + 1 + step
      asg == 1 ? nil : Lich::Gemstone::Armaments::ArmorStats.find_by_asg(asg)&.dig(:base_weight)
    end

    # The armor a worn item is by Lich's armor names, for an item INSPECT
    # has not been asked about. Many names are two words (leather tunic,
    # full plate, body armor) and a bare noun can be several sub-groups (a
    # tunic is robes or a leather breastplate), so the longest end of the
    # item's name that is an armor name decides. Normal clothing (ASG 1) is
    # not armor here: it is carried like anything worn.
    #
    # @param item [Lich::Common::Inventory::Item]
    # @return [Hash, nil] base_weight: the sub-group's standard weight, nil
    #   when the name fits sub-groups of different weights; nil when the name
    #   is no armor's
    # @api private
    def named_armor(item)
      words = (item.name || item.noun).to_s.downcase.split
      words = [item.noun.to_s.downcase] if words.empty?
      words.each_index do |from|
        found = Lich::Gemstone::Armaments::ArmorStats.find_all(words[from..].join(' ')).to_a
        found = found.reject { |asg| asg[:armor_sub_group] == 1 }
        next if found.empty?

        weights = found.map { |asg| asg[:base_weight] }.uniq
        return { base_weight: weights.size == 1 ? weights.first : nil }
      end
      nil
    rescue StandardError
      nil
    end

    # --- capacity, percent, learning -----------------------------------------

    # Capacity in pounds, the learned correction included.
    #
    # @param snapshot [Lich::Common::Inventory::Snapshot, nil] for the armor
    # @return [Float, nil] nil when the body weight is unknown
    def capacity(snapshot = nil)
      body = body_weight
      return nil unless body

      base_capacity(effective_str, body) + extras + (snapshot ? armor_adjustment(snapshot) : 0) + correction
    end

    # Encumbrance in percent of body weight, 0 when within capacity.
    #
    # @return [Float, nil]
    def percent(carried, capacity: self.capacity, body: body_weight)
      return nil unless capacity && body

      [((carried - capacity) / body) * 100, 0].max
    end

    # Pounds that can still be picked up before encumbrance (negative when over).
    #
    # @return [Float, nil]
    def room(snapshot, silver: Lich::Gemstone::Currency.silver.to_i)
      cap = capacity(snapshot)
      cap && cap - carried(snapshot, silver: silver)
    end

    # The learned correction: the middle of what the readings allow. With one
    # side only (never seen encumbered, say) the formula stands unless the
    # reading rules it out.
    #
    # @return [Float] 0 until something is learned
    def correction
      low, high = state.values_at(:low, :high)
      return 0.0 if low.nil? && high.nil?
      return [low.to_f, 0.0].max if high.nil?
      return [high.to_f, 0.0].min if low.nil?

      (low + high) / 2.0
    end

    # Narrow the correction from what the game says: the band it reports
    # (one of BANDS, the top of its step) for what is carried. A reading
    # that fits nothing learned so far starts over (gear or rounding moved);
    # a value not in BANDS teaches nothing.
    #
    # @param band [Integer] the game's encumbrance value
    # @param carried [Float]
    # @param model [Float] capacity without the correction
    # @param body [Float]
    # @return [Float] the correction now
    def learn(band, carried:, model:, body:)
      at = BANDS.index(band.to_i)
      return correction if at.nil?

      need = carried - model
      low, high = if at.zero?
                    [need, nil]
                  else
                    # past the band below, at most this one; the last has no top
                    [BANDS[at + 1] ? need - (band * body / 100.0) : nil, need - (BANDS[at - 1] * body / 100.0)]
                  end
      old_low, old_high = state.values_at(:low, :high)
      new_low = [low, old_low].compact.max
      new_high = [high, old_high].compact.min
      new_low, new_high = low, high if new_high && new_low && new_low > new_high
      remember(low: new_low, high: new_high)
      correction
    end

    # Learn from the game's encumbrance now and this snapshot.
    #
    # @return [Float, nil] the correction, nil when the body weight is unknown
    def observe(snapshot, band: XMLData.encumbrance_value, silver: Lich::Gemstone::Currency.silver.to_i)
      body = body_weight
      return nil unless body

      identify_armor(snapshot)
      model = base_capacity(effective_str, body) + extras + armor_adjustment(snapshot)
      learn(band.to_i, carried: carried(snapshot, silver: silver), model: model, body: body)
    end

    # What has been learned, kept in the character's libeo_carry profile
    # (EO::Settings), so every script that asks shares it.
    #
    # @api private
    def state
      (Settings.read(:libeo_carry) || {}).transform_keys(&:to_sym)
    end

    # @api private
    def remember(**values) = Settings.save_profile('libeo_carry', state.merge(values))

    # Forget what was learned (gear changed for good, say).
    #
    # @return [void]
    def reset! = Settings.save_profile('libeo_carry', state.slice(:simu_until, :simu_checked))

    # --- the floating disk (511) ---------------------------------------------

    # Air lore ranks for each item past the base 8 (wiki: Floating Disk).
    DISK_LORE = [10, 21, 33, 46, 60, 75, 91, 108, 126, 145, 165, 186, 208, 231].freeze
    DISK_POUNDS = 500

    # The disk's item limit: 8, more with Elemental Lore, Air; half the
    # ranks count when 511 is not known natively (a scroll or an item). A
    # disk someone else cast holds 8, which a refusal tells the caller.
    #
    # @return [Integer]
    def disk_limit(ranks: Skills.elemental_lore_air, native: Spell[511]&.known?)
      lore = native ? ranks.to_i : ranks.to_i / 2
      8 + DISK_LORE.count { |needed| needed <= lore }
    end

    # Items a disk holds by its count: everything inside counts, and a
    # locked treasure box a third of its items, rounded up. A locked box
    # hides how many it holds, so it counts as one, the least it can.
    #
    # @param disk [Lich::Common::Inventory::Item]
    # @return [Integer]
    def disk_items(disk)
      disk.children.sum { |item| item.opaque? ? 1 : 1 + disk_items(item) }
    end
  end
end
