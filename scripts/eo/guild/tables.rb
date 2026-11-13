# frozen_string_literal: true

module EO
  # The Adventurer's Guild: its tasks, the people who give and take them,
  # and the work each task asks for.
  module Guild
    # What the guild's tasks are made of: the towns, the people and how the
    # game names them, what they say, and the name each kind of task goes by
    # in a character's settings.
    module Tables
      module_function

      # The Bounty parser's name for a task, to the name a character's
      # settings know that kind of task by.
      TASK_TYPES = {
        :bandit_assignment   => "kill_bandits",
        :bandit              => "kill_bandits",
        :creature_assignment => "kill_creatures",
        :cull                => "culling",
        :dangerous           => "boss_culling",
        :escort              => "escort",
        :gem_assignment      => "gem_collecting",
        :gem                 => "gem_collecting",
        :heirloom_assignment => "heirloom_both",
        :heirloom            => "heirloom_both",
        :herb_assignment     => "foraging",
        :herb                => "foraging",
        :rescue_assignment   => "rescue",
        :rescue              => "rescue",
        :skin_assignment     => "skinning",
        :skin                => "skinning"
      }.freeze

      # What a taskmaster says when asked about a bounty.
      TASKMASTER_RESPONSES = Regexp.union(
        /The local gem dealer, .*, has an order to fill and wants our help./,
        /The local furrier .* has an order to fill and wants our help./,
        /It appears they have a .* problem they'd like you to solve./,
        /It appears that a local resident urgently needs our help in some matter.  Go report to .* to find out more./,
        /The local (healer|herbalist), .*, has asked for our aid./,
        /You have already been assigned a task, \w+./,
        /It appears they need your help in tracking down some kind of lost heirloom.  Go report to .* to find out more./,
        /Come back in about .* (?:minute|minutes) if you want another task./,
        /I have removed you from your current assignment/,
        /Who are you trying to ask/
      ).freeze

      # The furrier of each town, as the room shows them.
      FURRIER_NAMES = Regexp.union(
        /Bramblefist/i,
        /Delosa/i,
        /dwarven clerk/i,
        /furrier/i,
        /patchwork flesh merchant/i
      ).freeze

      # The gem dealer of each town.
      JEWELER_NAMES = Regexp.union(
        /areacne/i,
        /Brindlestoat/i,
        /dwarven clerk/i,
        /gem dealer/i,
        /jeweler/i,
        /plump purple-robed trader/i,
        /Zirconia/i
      ).freeze

      # The herbalist or healer of each town.
      HERBALIST_NAMES = Regexp.union(
        /Akrash/i,
        /alchemist/i,
        /brother Barnstel/i,
        /famed baker Leaftoe/i,
        /healer/i,
        /herbalist/i,
        /Libram Greenleaf/i,
        /Maraene/i,
        /merchant Kelph/i,
        /old Mistress Lomara/i,
        /scarred Agarnil kris/i,
        /Sparkfinger/i,
        /spectral quartermaster/i
      ).freeze

      # The herbalist's room in each town, as "u" and its uid.
      HERBALIST_UIDS = [
        'u4043601',    # Icemule Trace
        'u1015',       # Wehnimer's Landing
        'u3003056',    # Kharam-Dzu
        'u14103400',   # Ta'Vaalor
        'u13104200',   # Ta'Illistim
        'u4740011',    # Solhaven
        'u2101052',    # River's Rest
        'u13010004',   # Zul Logoth
        'u7118358',    # Kraken's Fall
        'u7503253',    # Hinterwilds
        'u3201291',    # Mist Harbor
        'u7150621',    # Sailor's Grief
      ].freeze

      # What a guard says when asked about a bounty.
      GUARD_RESPONSES = Regexp.union(
        /suppress bandit activity|bandits you encounter/,
        /particularly dangerous|cull their numbers|(?!.*bandit)suppress .* activity/,
        /SEARCH the area|do a thorough SEARCH/,
        /LOOT the item from its corpse/,
        /I don't have any tasks for you right now/,
        /Try bugging me later/,
        /Ah, so you have returned/,
        /You have completed your task/
      ).freeze

      # Every answer FORAGE gives.
      FORAGE_RESULT = Regexp.union(
        /^You begin to forage around when suddenly you feel a burning sensation in your hand\.$/,
        /^You begin to forage around when your hand comes into contact with something that stabs you in the finger\.$/,
        /^You forage/,
        /^You fumble about so badly in your search that you can only hope no one was watching you\.$/,
        /^You make so much noise that only the dead would not notice you thrashing about in your unsuccessful search\.$/,
        /^You stumble about in a fruitless attempt at foraging\.$/,
        /you are unable to find anything useful/,
        /^As you carefully forage around you (?:can find no (?:hint|trace)|see no evidence) of what you are looking for(?: right now, though you are fairly certain this is where it can be found)?\.(?:  You briefly wonder if it could even thrive in this place\.)?/,
        /^As you forage around you suddenly feel a sharp pain/,
      ).freeze

      # The answers that mean the hand was hurt.
      FORAGE_INJURY = Regexp.union(
        /^You begin to forage around when your hand comes into contact with something that stabs you in the finger./,
        /^As you forage around you suddenly feel a sharp pain in your/,
        /suddenly you feel a burning sensation in your hand/
      ).freeze

      # Every answer to taking something out.
      GET_RESULT = /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly )?(?:remove|draw|grab|reach|slip|tuck|retrieve|already have|unsheathe|detach|swap)|^Get what\?$|^Why don't you leave some for others\?$|^You need a free hand|^You already have that/

      # Every answer to putting something away.
      PUT_RESULT = /^You (?:put|(?:discreetly )?tuck|attach|toss|attempt to shield your|place|.* place|slip|wipe off the blade and sheathe|absent-mindedly drop|carefully add|find an incomplete bundle|untie your drawstring pouch)|^The .+ is already a bundle|^Your bundle would be too large if you if you tried to add that|^The .+ is too large to be bundled\.|^As you place your .+ inside your .+, you notice another .+ inside the .+ and carefully arrange the two .+ into a neat bundle\.|If you wish to continue, throw the item away again within fifteen seconds|you feel pleased with yourself at having cleaned up the surrounding area|over your shoulder|two items in that location|wear three functional items|^Your .*? won't fit in .*?\.$/

      # The room that stands for each town a task can name, as "u" and its
      # uid. Sailor's Grief (Contempt) is not here: see town_uids.
      TOWN_UIDS = {
        'Icemule Trace'      => 'u4042150',
        'Kharam-Dzu'         => 'u3001025',
        "Kraken's Fall"      => 'u7118221',
        'Mist Harbor'        => 'u3201029',
        "River's Rest"       => 'u2101008',
        'Solhaven'           => 'u4209030',
        'Vornavis'           => 'u4209030',
        "Ta'Illistim"        => 'u13100042',
        "Ta'Vaalor"          => 'u14100047',
        "Wehnimer's Landing" => 'u7120',
        'Zul Logoth'         => 'u13006016',
        'Cold River'         => 'u7503205'
      }.freeze

      # Sailor's Grief's room, in Shattered and elsewhere.
      CONTEMPT_UIDS = { 'GSF' => 'u7150607' }.freeze
      CONTEMPT_UID = 'u7150608'

      # The rooms of Sailor's Grief, on deck then below, where its taskmaster
      # wanders.
      SAILORS_GRIEF_UIDS = [
        7_150_601, 7_150_602, 7_150_603, 7_150_604, 7_150_605,
        7_150_606, 7_150_607, 7_150_608, 7_150_609, 7_150_610,
        7_150_611, 7_150_612, 7_150_613, 7_150_614, 7_150_615,
        7_150_616, 7_150_617, 7_150_621, 7_150_622
      ].freeze
      # The Hinterwilds guild room, where the taskmaster is Halfwhistle.
      HINTERWILDS_GUILD_UID = 7_503_207

      # @param game [String] the game's code
      # @return [Hash{String => String}] every town to its room
      def town_uids(game = XMLData.game)
        TOWN_UIDS.merge('Contempt' => CONTEMPT_UIDS.fetch(game, CONTEMPT_UID))
      end

      # @return [Array<Integer>] the herbalists' rooms that are on the map
      def herbalist_rooms
        HERBALIST_UIDS.map { |uid| Room[uid]&.id }.compact.select(&:positive?)
      end
    end
  end
end
