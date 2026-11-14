# frozen_string_literal: true

module EO
  # The hands: knowing what they hold, freeing one, taking an item into one,
  # wearing an item, putting one into a container, and the READY list's
  # STORE and READY. Each answers with a word for what happened; what to say
  # about it, and whether to stop, is the calling script's.
  #
  # Commands go through the running script's helpers (EO.use). The helpers
  # this needs: command(text, pattern) answering the lines, and
  # result(text, pattern = nil) answering one line, the first line back when
  # no pattern is given.
  module Hands
    module_function

    # Every answer to taking something out or drawing it.
    GET = Regexp.union(
      /^You (?:shield the opening of .*? from view as you |discreetly |carefully |deftly |slowly |quickly )?(?:remove|pick up|draw|equip|grab|reach|slip|tuck|retrieve|already have|unsheathe|detach|swap|sling|withdraw)/,
      /^With subtle movements, you sneak a hand/,
      /^Get what\?$/,
      /^Why don't you leave some for others\?$/,
      /^You need a free hand/,
      /^You already have that/,
      /Reaching over your shoulder/,
      /^As you draw/,
      /^Ribbons of.*?light/,
      /^You are already holding/
    )

    # Every answer to putting something away.
    PUT = Regexp.union(
      /You/,
      /Spreading your wings/,
      /I could not find what you were referring to/,
      /Draping the/,
      /Heedful of your surroundings/,
      /won't fit/,
      /crumbles? and decays? away/,
      /crumbles? into a pile of dust/,
      /That is not yours/,
      /Hey, that belongs to/,
      /Get what/,
      /Reaching over your shoulder/,
      /An ethereal.*?light swirls/,
      /As you move to put away your (?:<a exist="\d+" noun="\w+">[^<]+<\/a>|[\w-]+), it reverts to its normal state\./
    )

    # A take's answer when the item is not where it was thought to be.
    MISSING = /Get what|I could not find what you were referring to/
    # A take's answer when the item is too heavy to pick up.
    OVERLOADED = /You are unable to handle the additional load/

    # @param obj [GameObj]
    # @return [Boolean] whether a hand holds it. Nothing, and an object with no
    #   id, is in neither hand.
    def holding?(obj)
      return false if obj.nil? || obj.id.nil?

      Lich::Stash.in_hand?(obj)
    end

    # Make a hand free. Nothing is done when one already is and its arm can
    # be used. Otherwise the left is emptied when it is favoured and usable,
    # or when the right arm is beyond use; else the right. With both arms
    # beyond use neither is.
    #
    # @param favor_left [Boolean]
    # @param empty [Proc] given :left or :right, puts away what that hand holds
    # @return [Symbol] :free, or :crippled when no hand could be chosen
    def free_hand(favor_left:, empty:)
      right_usable = [Wounds.rightArm, Wounds.rightHand, Scars.rightArm, Scars.rightHand].max < 3
      right_hand_free = GameObj.right_hand.id.nil? && right_usable

      left_usable = [Wounds.leftArm, Wounds.leftHand, Scars.leftArm, Scars.leftHand].max < 3
      left_hand_free = GameObj.left_hand.id.nil? && left_usable
      return :free if right_hand_free || left_hand_free

      waitrt?

      if (favor_left && left_usable) || !right_usable
        return :crippled unless left_usable

        empty.call(:left)
      else
        empty.call(:right)
      end
      :free
    end

    # Take an item from a container or the ground into a hand that is
    # already free, and wait to see it there. The closed containers a
    # carried item is inside are opened first.
    #
    # @param item [GameObj]
    # @param to [String] 'right' or 'left'
    # @return [Symbol] :held, :overloaded (too heavy), :missing (the game
    #   could not find it), or :failed (no such answer, and not in hand
    #   after five seconds)
    def take(item, to)
      refused = Regexp.union(MISSING, OVERLOADED)
      # a carried item in a closed container: Lich's Stash opens the way to it
      Lich::Stash.open_path_to(item)
      line = EO.result("_drag ##{item.id} #{to}", Regexp.union(GET, refused))

      20.times do
        return :held if holding?(item)
        break if line =~ refused
        sleep 0.1
      end

      # a drag the game did not answer in time gets as long again as a
      # sale does
      unless line =~ refused
        30.times do
          return :held if holding?(item)
          sleep 0.1
        end
      end

      return :overloaded if line =~ OVERLOADED
      return :missing if line =~ MISSING

      :failed
    end

    # Wear an item held in a hand.
    #
    # @param item [GameObj]
    # @return [Symbol] :worn, :stuck (still in the hand), or :unseen (out of
    #   the hand but not seen among what is worn)
    def wear(item)
      line = EO.result("_drag ##{item.id} wear")

      20.times do
        return :worn if !holding?(item) && GameObj.inv.map(&:id).compact.include?(item.id)
        break if line =~ /You can't wear that/
        sleep 0.1
      end

      holding?(item) ? :stuck : :unseen
    end

    # Put an item into a container, up to five tries, opening the container
    # when it answers closed.
    #
    # @param bag [GameObj]
    # @param item [GameObj]
    # @param loose [Boolean] the container shows no contents (a weapon
    #   displayer): the item leaving the hand is proof enough
    # @param on_closed [Proc, nil] given the bag when it answered closed,
    #   before it is opened for the second try
    # @param ensure_open [Proc, nil] given the bag when its contents are not
    #   known after the put, to open it and look in
    # @return [Symbol] :not_yours, :gone (not in hand to begin with, or
    #   already taken), :unlootable (it cannot be held), :full, :crumbled,
    #   :stored, or :failed after five tries
    def store(bag, item, loose: false, on_closed: nil, ensure_open: nil)
      5.times do
        lines = EO.command("_drag ##{item.id} ##{bag.id}", PUT)

        if lines.any? { |l| l =~ /You can't.*?It's closed!/ }
          on_closed&.call(bag)
          EO.result("open ##{bag.id}", Containers::OPEN)
          lines = EO.command("_drag ##{item.id} ##{bag.id}", PUT)
        end

        lines.each do |line|
          return :not_yours if line.match?(/Hey, that belongs to/)
          return :gone if line.match?(/You are unable to handle|That is not yours|Get what|I could not find what you were referring/)
        end

        return :unlootable if lines.any? { |l| l =~ /put something that you can't hold/ }

        return :full if lines.any? { |l| l =~ /won't fit/i }
        return :crumbled if lines.any? { |l| l =~ /crumbles? and decays? away|crumbles? into a pile of dust/i }

        ensure_open&.call(bag) unless bag.contents.is_a?(Array) || loose

        20.times do
          return :stored if !holding?(item) && bag.contents.to_a.map(&:id).include?(item.id)
          return :stored if loose && !holding?(item)

          sleep 0.1
        end

        # a container the game sends no updates for (a disk) keeps what Lich
        # last saw in it: look in once before dragging again
        unless loose || holding?(item)
          EO.command("look in ##{bag.id}", Containers::LOOK, silent: true, quiet: true)
          return :stored if bag.contents.to_a.map(&:id).include?(item.id)
        end

        waitrt?
      end

      :failed
    end

    # --- the READY list ---------------------------------------------------

    # @param key [String, Symbol] a READY list key
    # @return [String, Symbol] the word READY and STORE take for it
    def ready_word(key)
      case key.to_s
      when 'secondary_weapon' then '2weapon'
      when 'ranged_weapon'    then 'ranged'
      else key
      end
    end

    # Put a READY list item away with STORE, up to ten tries. Its sheath is
    # seen to first when STORE is set to put it in one.
    #
    # @param key [String, Symbol] the item's READY list key
    # @param item [GameObj]
    # @param ensure_open [Proc, nil] given the sheath, to open it
    # @return [Boolean] whether it left the hand; true when the key holds nothing
    def stow_ready(key, item, ensure_open: nil)
      return true if ReadyList.ready_list[key.to_sym].nil?

      if ReadyList.store_list[key.to_sym] =~ /put in sheath/
        ensure_open&.call(ReadyList.ready_list[:sheath])
      elsif ReadyList.store_list[key.to_sym] =~ /put in secondary/
        ensure_open&.call(ReadyList.ready_list[:secondary_sheath])
      end

      10.times do
        EO.result("store #{ready_word(key.to_s)}", PUT)
        sleep 0.2
        return true unless holding?(item)
      end

      false
    end

    # Bring a READY list item back to hand with READY, up to ten tries.
    #
    # @param key [String, Symbol] the item's READY list key
    # @param item [GameObj]
    # @return [Boolean] whether it is in hand; true when the key holds nothing
    def return_ready(key, item)
      return true if ReadyList.ready_list[key.to_sym].nil?

      10.times do
        EO.result("ready #{ready_word(key.to_s)}", GET)
        sleep 0.2
        return true if holding?(item)
      end

      false
    end
  end
end
