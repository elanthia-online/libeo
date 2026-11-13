# frozen_string_literal: true

module EO
  # Selling one item to a shop, and asking a shop what an item is worth.
  #
  # Commands go through the running script's helpers (EO.use). The helper
  # this needs: command(text, pattern) answering the lines.
  module Selling
    module_function

    # A shop that will not take the item.
    REFUSED = /What were you referring to\?|That's not quite my field|That's basically worthless here|Can't say I'm interested in that|This is a pawnshop, sir, not a junkshop|The company don't buy trash|as if you were a lunatic/

    # The figure in a shop's answer to APPRAISE.
    WORTH = /([,0-9]+) (?:silver|for it if you want to sell|for this if you'd like)/

    # SELL an item held in a hand, and give it two seconds to leave the hand.
    #
    # @param item [GameObj]
    # @return [Symbol] :refused, or :offered. An offered item may still be
    #   in the hand: the wait is not a test.
    def sell(item)
      lines = EO.command("sell ##{item.id}", /You (offer to sell|ask)|What were you referring to\?/)
      return :refused if lines.any?(REFUSED)

      20.times do
        break unless Hands.holding?(item)
        sleep 0.1
      end
      :offered
    end

    # Ask the shop to APPRAISE an item.
    #
    # @param item [GameObj]
    # @return [Array<String>] the answer's lines
    def appraise(item)
      EO.command("appraise ##{item.id}", /^You ask .*to appraise/)
    end

    # What an appraisal says the item is worth.
    #
    # @param lines [Array<String>, String]
    # @return [Hash{Symbol => Object}, nil] raw: the figure as written,
    #   amount: as a number; nil when the answer names none
    def worth(lines)
      line = Array(lines).find { |l| l =~ WORTH }
      return nil unless line && line =~ WORTH

      raw = Regexp.last_match(1)
      { raw: raw, amount: raw.delete(',').to_i }
    end
  end
end
