# frozen_string_literal: true

module EO
  # Getting boxes opened: the town locksmith, who is rung for, quotes a fee
  # and is paid; and the locksmith pool, which takes a box with a tip and
  # gives it back later.
  #
  # Commands go through the running script's helpers (EO.use). The helper
  # this needs: command(text, pattern, silent:, quiet:, timeout:) answering
  # the lines.
  module Locksmith
    module_function

    # The outer wagon at Kraken's Fall: the locksmith is a step east of it.
    KRAKENS_FALL_WAGON_UID = 7_118_381

    # The town locksmith will not work on a box of these nouns, held or not.
    POOL_ONLY_NOUNS = /\Acase\z/i

    # What a town locksmith answers when rung for.
    QUOTE = /Gimme ([\d,]+) silvers|ignores you/
    # What PAY answers.
    PAID = /accepts|have enough/

    # How the town locksmith here is called: by what is on the table or
    # counter, a bell or keys first, a chime on it or in the room last.
    #
    # @return [String, Symbol] the command to send; or :no_table,
    #   :no_contents (the table would not show what is on it), :nothing
    #   (none of the three is there)
    def town_activator
      table = (GameObj.room_desc.to_a + GameObj.loot.to_a).find { |obj| obj.noun =~ /(?:table|counter)$/ }
      return :no_table unless table

      EO.command("look on ##{table.id}", /On the/) if table.contents.nil?
      return :no_contents if table.contents.nil?

      if table.contents.any? { |obj| obj.noun == 'bell' }
        'ring bell'
      elsif table.contents.any? { |obj| obj.noun == 'keys' }
        'pull keys'
      elsif table.contents.any? { |obj| obj.noun == 'chime' } || GameObj.loot.any? { |obj| obj.noun == 'chime' }
        'ring chime'
      else
        :nothing
      end
    end

    # @param box [GameObj]
    # @return [Boolean] whether LOOK IN shows the box closed or phased
    def shut?(box)
      lines = EO.command("look in ##{box.id}", /<container|That is closed|You see the shifting form/, silent: true, quiet: true)
      lines.any? { |line| line =~ /That is closed|You see the shifting form/i }
    end

    # OPEN a box to see whether it is locked.
    #
    # @param box [GameObj]
    # @return [Boolean] whether it is locked
    def locked?(box)
      lines = EO.command("open ##{box.id}", /That is already open|You open|You throw back|It appears to be locked/, silent: true, quiet: true)
      lines.any?(/locked/)
    end

    # Call the town locksmith, with the locked box in hand.
    #
    # @param activator [String] from town_activator
    # @return [String, nil] the answer: a quote, or being ignored; nil when
    #   nothing answered in two seconds
    def call(activator)
      dothistimeout(activator, 2, QUOTE)
    end

    # @param answer [String, nil] what the locksmith said when called
    # @return [Integer, nil] the fee quoted
    def fee(answer)
      answer.to_s[/Gimme ([\d,]+) silvers/, 1]&.delete(',')&.to_i
    end

    # PAY the fee quoted.
    #
    # @return [String, nil] the answer: "accepts", or not "have enough"; nil
    #   when nothing answered in two seconds
    def pay
      dothistimeout('pay', 2, PAID)
    end

    # The locksmith pool.
    module Pool
      module_function

      # What giving a box to the worker answers.
      GIVE = /You want a locksmith|You don't have|takes your|already holding as many boxes|already (unlocked|open)/
      # What asking for a box back answers.
      RETURN = /We don't have any boxes ready for you|We don't seem to have that box|Alright, here's your|You need to lighten your load first|You can't hold anymore items/
      # The line a pool list opens with.
      LIST_HEADER = /here's the list of boxes we have for you\.|You haven't given us any boxes to be worked on\./

      # The boxes to drop off, in order. A box already in hand goes first:
      # otherwise it is handed in on another box's turn and cannot be found
      # when its own comes.
      #
      # @param held [Array<GameObj>] both hands
      # @param found [Array<GameObj>] boxes found in containers
      # @param passed [Array<GameObj>] boxes the caller named
      # @return [Array<GameObj>]
      def order(held:, found:, passed:)
        (held.select { |hand| hand.type =~ /box/ } + found + passed).uniq(&:id)
      end

      # GIVE the worker the box in the right hand, with a tip.
      #
      # @param worker [GameObj]
      # @param tip [String, Integer] the tip, "5 PERCENT" or an amount
      # @param confirm [Boolean] the second GIVE, which confirms the first
      # @return [String, nil] the answer, of GIVE; nil after three seconds
      def give(worker, tip, confirm: false)
        dothistimeout("give ##{worker.id} #{tip}#{confirm ? ' confirm' : ''}", 3, GIVE)
      end

      # ASK the worker for a box back. The wait is long enough to outlast
      # lag: an answer that comes after giving up hands over a box nothing
      # then opens.
      #
      # @param worker [GameObj]
      # @return [String, nil] the answer, of RETURN; nil after fifteen seconds
      def ask_return(worker)
        dothistimeout("ask ##{worker.id} for return", 15, RETURN)
      end

      # The box the worker just handed back, given two seconds to arrive.
      #
      # @return [GameObj, nil] a box or plinite in the right hand, else the
      #   left; nil when neither holds one
      def returned_box
        20.times do
          break if [GameObj.right_hand, GameObj.left_hand].map(&:type).compact.join(',') =~ /box|plinite/
          sleep 0.1
        end
        if GameObj.right_hand.type =~ /box|plinite/
          GameObj.right_hand
        elsif GameObj.left_hand.type =~ /box|plinite/
          GameObj.left_hand
        end
      end

      # How many boxes the pool holds that are not ready to come back, from
      # the worker's list. A list cut short is counted again from the
      # session's whole buffer, when this list's header was seen: without it
      # the buffer's last list may be an old one.
      #
      # @param worker [GameObj]
      # @return [Array(Integer, Boolean)] the count, and whether the list
      #   came back whole
      def depth(worker)
        list_match = Regexp.union(LIST_HEADER, /^(\d+)\./)
        results = EO.command("ask ##{worker.id} about list", list_match, silent: true, quiet: true, timeout: 15)
        total, returned = counts(results)

        whole = results.last =~ /<prompt/ ? true : false
        if !whole && results.any? { |line| line =~ LIST_HEADER }
          buffered_total, buffered_returned = counts(Array(reget))
          # >=: Lich buffers a line before a script reads it, so the buffer
          # is at least as complete; on a tie it may hold the last box's
          # status, which the lines read were cut before
          total, returned = buffered_total, buffered_returned if buffered_total >= total
        end

        [total - returned, whole]
      end

      # Count the boxes, and the ones ready to come back, in the last pool
      # list among some lines.
      #
      # @param lines [Array<String>]
      # @return [Array(Integer, Integer)] the boxes, and those ready
      def counts(lines)
        start = lines.rindex { |line| line =~ LIST_HEADER }
        return [0, 0] unless start

        list = lines.drop(start)
        total = list.reverse_each.find { |line| line =~ /^\s*\d+\.\s+An?\s/ }.to_s[/\d+/].to_i
        [total, list.count { |line| line =~ /It is ready to be RETURNED\./ }]
      end

      # The tip for the next boxes when tipping rises with how full the pool is.
      #
      # @param pool_count [Integer] boxes in the pool now
      # @param boxes [Integer] boxes about to go in
      # @param base [Numeric] the tip for an empty pool
      # @param max [Numeric] the tip for a full one
      # @param alpha [Numeric] how sharply it rises
      # @return [Integer]
      def tip_for(pool_count, boxes, base:, max:, alpha:)
        tip_amount = 0
        upper_limit = [pool_count + boxes, 100].min
        pool_count += 1

        (pool_count..upper_limit).each { |box_no| tip_amount += tip(box_no, base, max, alpha) }

        tip_amount.ceil
      end

      # The tip for the box that takes one place in the pool's hundred.
      #
      # @param box_no [Integer] the place, 1 to 100
      # @return [Integer]
      def tip(box_no, base, max, alpha)
        factor = box_no.to_f / 100
        adjusted_tip = base.to_i + ((factor**alpha.to_f) * (max.to_i - base.to_i))
        adjusted_tip.round
      end
    end
  end
end
