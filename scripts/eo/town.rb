# frozen_string_literal: true

module EO
  # The town around the character: which shop to walk to and whether to go
  # at all, a shop in a bounty's town when it is in the same region, Four
  # Winds Isle and the way off it, the trash receptacle, and the locksmith
  # pool's worker.
  #
  # Commands and walks go through the running script's helpers (EO.use).
  # The helpers this needs: command(text, pattern, silent:, quiet:)
  # answering the lines, go(place), and say(type:, text:).
  module Town
    module_function

    FWI = /Four Winds|Mist Harbor|Western Harbor/

    # Coldriver Village in the Hinterwilds has a gemshop, a furrier and the
    # locksmith pool, and none of SHOPS_ELSEWHERE: the nearest of those on
    # the map is a long way off.
    HINTERWILDS_TOWN_UID = 7503205
    SHOPS_ELSEWHERE = /collect|pawnshop|consignment|chronomage/

    # Rooms a path leaves the region by: a ferry, a mine cart, a transport
    # or a portmaster.
    REGION_EDGE_UIDS = [
      14_001_002, # Ta'Vaalor Ferry
      13_002_021, # Western Spine Mine Cart
      13_003_019, # Eastern Spine Mine Cart
      373_014,    # River's Rest Boot
      7_503_001,  # Hinterwilds Caravan Dropoff
      13_205_202, # EN Hinterwilds Transport
      4_132_054,  # IMT Hinterwilds Transport
      7111,       # Portmaster - Wehnimer's Landing
      3_002_033,  # Portmaster - Teras Isle
      2_101_030,  # Portmaster - River's Rest
      4_744_014,  # Portmaster - Solhaven
      7_118_259,  # Portmaster - Kraken's Fall
      7_136_032,  # Portmaster - Ta'Vaalor
      7_133_026   # Portmaster - Icemule Trace
    ].freeze

    # The room on Four Winds Isle that counts as its town, and the dock the
    # way off starts from.
    FWI_TOWN = 3668
    FWI_DOCK = 3669

    # What the locksmith pool's worker is called, where the room does not say.
    POOL_WORKERS = %w[worker trickster Jahck woman attendant gnome merchant dwarf].freeze

    # @param room [Room]
    # @return [Boolean] whether the room is on Four Winds Isle
    def fwi?(room)
      room.location.to_s =~ FWI ? true : false
    end

    # Whether a shop is one this town does not have, so that going to the
    # nearest would mean leaving the area. Only the Hinterwilds town counts,
    # and not for a character willing to travel to sell.
    #
    # @param shop [String] a shop tag
    # @param travels [Boolean] the character sells on Four Winds Isle
    # @return [Boolean]
    def shop_elsewhere?(shop, travels: false)
      return false unless shop.to_s =~ SHOPS_ELSEWHERE
      return false if travels

      town = Room.current.find_nearest_by_tag('town')
      return false if town.nil?

      Room[town].uid.first == HINTERWILDS_TOWN_UID
    end

    # Where to sell at a kind of shop, and whether to go at all. Use this
    # and not find_nearest_by_tag: that searches the whole map, and in a town
    # without the shop answers with one on the far side of the continent.
    #
    # @param shop [String] a shop tag
    # @param travels [Boolean] see shop_elsewhere?
    # @return [Integer, nil] the room id, nil to skip this shop
    def nearest_shop(shop, travels: false)
      return nil if shop_elsewhere?(shop, travels: travels)

      Room.current.find_nearest_by_tag(shop)
    end

    # The room tagged +tag+ nearest each town, by the town's location.
    #
    # @param tag [String]
    # @param towns [Array<Room>] the rooms tagged town
    # @return [Hash{String => Room}]
    def by_town(tag, towns)
      EO.say(type: 'debug', text: "tag: #{tag}")
      towns.to_h { |town| [town.location, Room[town.find_nearest_by_tag(tag)]] }
    end

    # @param town [String] a town's name, matched loosely against the locations
    # @param tag [String]
    # @param towns [Array<Room>]
    # @return [Room, nil]
    def in_town(town, tag, towns)
      EO.say(type: 'debug', text: "tag: #{tag} | town: #{town}")
      match = by_town(tag, towns).find { |location, _room| location.downcase.include?(town.downcase) }
      match&.last
    end

    # A shop in a bounty's town, when the walk there stays in the region.
    #
    # @param place [String] the shop's tag
    # @param town [String] the bounty's town; "Cold River" is the Hinterwilds
    # @param towns [Array<Room>]
    # @return [Integer, nil] the room id, nil when unknown or out of the region
    def in_region(place, town:, towns:)
      EO.say(type: 'debug', text: "place: #{place}")

      town = 'Hinterwilds' if town.eql?('Cold River')
      destination = in_town(town, place, towns)
      return nil unless destination

      place = destination.id
      return place if Room.current.eql?(Room[place])

      path = Room.current.path_to(Room[place])
      return nil unless path

      edges = REGION_EDGE_UIDS.map { |uid| Map.ids_from_uid(uid).first }
      (path & edges).empty? ? place : nil
    end

    # Leave Four Winds Isle when the character's town is there: walk to the
    # dock, then to the return room, or turn the trinket when none is set.
    #
    # @param trinket [String, nil] the trinket's name
    # @param return_room [Integer, String, nil]
    # @return [Symbol] :elsewhere (not on the isle; nothing done),
    #   :no_trinket (on the isle with no trinket named; nothing done), or :left
    def leave_fwi(trinket:, return_room:)
      return :elsewhere unless Room.current.find_nearest_by_tag('town') == FWI_TOWN
      return :no_trinket if trinket.nil?

      EO.go2(FWI_DOCK)
      if return_room.nil?
        worn = GameObj[trinket].nil? ? false : true
        fput "get my #{trinket}" unless worn
        fput "turn ##{GameObj[trinket].id}"
        fput "stow my #{trinket}" unless worn
      else
        EO.go2(return_room)
      end
      :left
    end

    # The room's trash receptacle, asked of TRASH.
    #
    # @return [GameObj, Array<String>, nil] the receptacle; nil when the game
    #   says there is none; the answer's lines when it named none either way,
    #   which a caller testing for nil takes as one being there
    def trash_can
      lines = EO.command('trash', /You could discard items|You do not notice/, silent: true, quiet: true)
      return nil if lines.any? { |line| line =~ /You do not notice a trash receptacle here/ }

      lines.each do |line|
        if (found = line.match(/You could discard items in (?:an?|the) <a exist="(?<exist>-?\d+)" noun="(?<noun>.*?)">(?<name>.*?)<\/a>/))
          return GameObj.new(found[:exist], found[:noun], found[:name])
        end
      end
    end

    # The locksmith pool's worker, by the name the room's tag gives or by
    # POOL_WORKERS, looking up to twenty times.
    #
    # @return [Array(GameObj, Array<String>)] the worker, nil when not found,
    #   and the lines of the last LOOK
    def pool_worker
      worker = nil
      lines = nil
      name = Regexp.last_match(1) if Room.current.tags.find { |tag| tag =~ /meta:boxpool:npc:(.*)/ }
      name ||= POOL_WORKERS

      20.times do
        worker = GameObj.npcs.find { |obj| obj.name =~ Regexp.union(name) }
        break if worker

        lines = EO.command('look', /<resource picture/, silent: true, quiet: true)
        sleep 0.1
      end
      [worker, lines]
    end
  end
end
