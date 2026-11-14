# frozen_string_literal: true

module EO
  # Things done to one item: throwing it away unless it is marked, phasing
  # a box and bringing it back, lifting a curse, and waiting for the disk
  # that follows the character.
  #
  # Commands go through the running script's helpers (EO.use). The helpers
  # this needs: command(text, pattern, silent:, quiet:) answering the lines,
  # result(text, pattern) answering one line, and wait().
  module Items
    module_function

    # @param obj [GameObj]
    # @return [Boolean] whether MARK has the item as unsellable
    def marked?(obj)
      lines = EO.command("mark ##{obj.id} status", /is not marked as unsellable|has been marked as unsellable/, silent: true, quiet: true)
      lines.any? { |line| line =~ /has been marked as unsellable/ }
    end

    # Throw away an item held in a hand, trying while it stays there. An
    # item marked unsellable is not thrown.
    #
    # @param obj [GameObj]
    # @param command [String] "trash" or "drop"
    # @param attempts [Integer]
    # @param poll [Boolean] watch the hand for a second after each try, for
    #   an item that gives no roundtime, where otherwise roundtime is waited out
    # @param on_marked [Proc, nil] called when the item turns out marked
    # @return [Symbol] :marked, :tossed, or :kept (still in hand)
    def toss(obj, command, attempts: 1, poll: false, on_marked: nil)
      if marked?(obj)
        on_marked&.call
        return :marked
      end

      attempts.times do
        break unless Hands.holding?(obj)

        fput("#{command} ##{obj.id}")

        if poll
          10.times do
            break unless Hands.holding?(obj)
            sleep 0.1
          end
        else
          EO.settle
        end
      end

      Hands.holding?(obj) ? :kept : :tossed
    end

    # Phase a box (704) so it weighs nothing, casting again through spell
    # hindrance while the mana lasts. Enruned and mithril boxes are left.
    #
    # @param box [GameObj]
    # @return [void]
    def phase(box)
      return unless box.type =~ /box/
      return if box.name =~ /enruned|mithril/i
      return unless Spell[704].known? && Spell[704].affordable?

      loop do
        cast_result = Spell[704].cast("at ##{box.id}")
        break unless cast_result =~ /^\[Spell Hindrance for/ && Spell[704].affordable?
      end
    end

    # Bring a phased box back by dropping it, which puts it in a hand again.
    #
    # @param box [GameObj]
    # @return [GameObj, nil] the box as it is now: the same one when it was
    #   not phased, else the box found in a hand
    def unphase(box)
      lines = EO.command("look at ##{box.id}", /You see/, silent: true, quiet: true)
      return box unless lines.any? { |line| line =~ /shifting/i }

      dothistimeout("drop ##{box.id}", 3, /flickers in and out of existence/)
      EO.settle

      EO.command('glance hands', /<(right|left)/, silent: true, quiet: true)

      [GameObj.right_hand, GameObj.left_hand].find { |hand| hand.type =~ /box/ }
    end

    # Make a cursed item safe to pick up: Remove Curse (315) when known,
    # with a mana pulse when it cannot be afforded; else an eonake gauntlet,
    # moved to the hand that will do the picking up.
    #
    # @param obj [GameObj] the cursed item
    # @param gauntlet [GameObj, nil] a worn eonake gauntlet
    # @return [Symbol] :lifted, :no_mana (315 is known and cannot be
    #   afforded), or :cannot
    def lift_curse(obj, gauntlet: nil)
      Lich::Gemstone::Mana.pulse(315)

      return :no_mana if Spell[315].known? && !Spell[315].affordable?

      if Spell[315].known? && Spell[315].affordable?
        Spell[315].cast("at ##{obj.id}")
        return :lifted
      end

      unless gauntlet.nil?
        lines = EO.command("look ##{gauntlet.id}", /You are currently wearing the <a exist="[^"]+" noun="gauntlet">eonake gauntlet<\/a>/, silent: true, quiet: true)
        gauntlet_hand = Regexp.last_match(1) if lines.any? { |l| l =~ /(right|left) hand/ }

        if GameObj.right_hand.name == 'Empty'
          return :lifted if gauntlet_hand == 'right'

          if gauntlet_hand == 'left'
            move_gauntlet(gauntlet, :right)
            return :lifted
          end
        end

        if GameObj.left_hand.name == 'Empty'
          return :lifted if gauntlet_hand == 'left'

          if gauntlet_hand == 'right'
            move_gauntlet(gauntlet, :left)
            return :lifted
          end
        end
      end

      :cannot
    end

    # Take the gauntlet off, see it into the hand it is wanted on, wear it.
    #
    # @api private
    # @param gauntlet [GameObj]
    # @param side [Symbol] :right or :left, the hand it should end up on
    def move_gauntlet(gauntlet, side)
      EO.result("remove ##{gauntlet.id}", /You slip the gauntlet from/)
      # read after the REMOVE: it lands in whichever hand is free
      hand = side == :right ? GameObj.right_hand : GameObj.left_hand
      EO.result('swap', /You swap/) unless hand.id == gauntlet.id
      EO.result("wear ##{gauntlet.id}", /You slip the eonake gauntlet over/)
    end

    # Wait up to five seconds for the character's disk when it has fallen
    # behind or gone.
    #
    # @param disk [GameObj] the disk as the script last knew it
    # @param on_wait [Proc, nil] called once when there is a wait to make
    # @return [GameObj, nil] the disk now, nil when it did not come
    def await_disk(disk, on_wait: nil)
      if disk.status&.include?('gone') || ::Disk.mine.nil?
        on_wait&.call

        50.times do
          break if ::Disk.mine
          sleep 0.1
        end
      end

      ::Disk.mine ? GameObj[::Disk.mine.id] : nil
    end
  end
end
