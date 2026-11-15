# frozen_string_literal: true

module EO
  # Treasure boxes: opening one and showing what is in it, the answers to
  # taking its coins, and which emptied box is worth keeping.
  #
  # Commands go through the running script's helpers (EO.use). The helpers
  # this needs: command(text, pattern, silent:, quiet:) answering the lines,
  # and result(text, pattern) answering one line.
  module Boxes
    module_function

    # The answers to GET COINS FROM a box.
    COINS = /You gather the remaining|Get what|You can only collect|You cannot hold any more silvers/
    # The last of the coins came out.
    COINS_DONE = /You gather the remaining/
    # The character can carry no more silver.
    COINS_FULL = /You can only collect|You cannot hold any more silvers/

    # A box made of something worth selling empty.
    VALUABLE = /gold|mithril|silver/

    # OPEN a box.
    #
    # @param box [GameObj]
    # @return [String, nil] the game's answer, which says "locked" for one
    #   that is; nil when nothing answered
    def open(box)
      EO.result("open ##{box.id}", /open|locked/)
    end

    # LOOK IN a box, so Lich learns its contents.
    #
    # @param box [GameObj]
    # @param quiet [Boolean] keep the listing off the screen
    # @return [Array<String>] the answer's lines
    def look_in(box, quiet: true)
      EO.command("look in ##{box.id}", Containers::LOOK, silent: quiet, quiet: quiet)
    end

    # Take coins from an open box, once.
    #
    # @param box [GameObj]
    # @param charm [GameObj, nil] a coin charm to POINT at the box instead
    # @return [String, nil] the game's answer: of COINS for a GET, the
    #   charm's summoning line for a POINT
    def take_coins(box, charm: nil)
      return EO.result("point ##{charm.id} at ##{box.id}", /You summon/) unless charm.nil?

      EO.result("get coins from ##{box.id}", COINS)
    end

    # Whether an emptied box is kept and not thrown away: an empty valuable
    # one when boxes are sold, and a reliquary always.
    #
    # @param box [GameObj]
    # @param sell [Boolean] boxes are among what the character sells
    # @return [Boolean]
    def keep?(box, sell:)
      (sell && box.contents.empty? && box.name =~ VALUABLE) || box.name =~ /reliquary/i ? true : false
    end
  end
end
