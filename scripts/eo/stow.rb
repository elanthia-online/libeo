# frozen_string_literal: true

module EO
  # Putting an item where the STOW list says: its type's bag, else the
  # default, else the overflow bags in number order, past the bags known
  # to be full. One per script; it keeps which bags filled up.
  class Stow
    OVERFLOW = /\Aoverflow_container_?(\d*)\z/
    # Seconds a bag counts as "just opened": one found closed again inside
    # them closed itself.
    JUST_OPENED = 60

    # @return [Hash{String => Array}] full bags by name, with when, where
    #   and the item that did not fit
    attr_accessor :full

    # @param bags [Hash{Symbol => GameObj}, nil] the bags by type; nil reads
    #   Lich's StowList.stow_list afresh each time, as STOW changes
    # @param learned [Proc, nil] given (:auto_close, bag), (:crumbly, item) or
    #   (:unlootable, item) when a put teaches something worth keeping
    def initialize(bags: nil, learned: nil)
      @list = bags
      @learned = learned || ->(_kind, _obj) {}
      @full = {}
      @snapshot = nil
      @added = Hash.new(0)
      @moved = []
      @opened = {}
    end

    # --- weights, from the inventory feed -----------------------------------

    # Take the inventory feed's snapshot for this looting pass: every item's
    # weight (on the floor too, a locked box with what it holds) and every
    # bag's room. What this pass puts away is counted from here. The weights
    # are only good for the pass: hand over nil when it ends, or a bag emptied
    # since is still passed over as full.
    #
    # @param snapshot [Lich::Common::Inventory::Snapshot, nil] nil forgets the
    #   last one, so every put is tried
    # @return [void]
    def observe(snapshot)
      @snapshot = snapshot
      @added = Hash.new(0)
      @moved = []
    end

    # @param item [GameObj]
    # @return [Integer, nil] its weight, nil when the snapshot does not know it
    def weight_of(item)
      known = @snapshot && @snapshot[item.id]
      known&.total_weight
    end

    # @param bag [GameObj]
    # @return [Float, nil] pounds a bag can still take, nil when unknown (no
    #   snapshot, or a bag limited by count rather than weight)
    def room_in(bag)
      known = @snapshot && @snapshot[bag.id]
      left = known&.space_left
      left && left - @added[bag.id]
    end

    # Whether a bag can take an item by weight; true when either is unknown,
    # so the put is tried as before.
    #
    # @return [Boolean]
    def fits?(bag, item)
      weight = weight_of(item)
      room = room_in(bag)
      weight.nil? || room.nil? || weight <= room
    end

    # @return [Hash{Symbol => GameObj}]
    def bags = @list || StowList.stow_list

    # @return [Array<GameObj, nil>] the overflow bags in number order, nil
    #   for one listed but not found
    def overflow
      bags.keys.select { |key| key.to_s.match?(OVERFLOW) }.sort_by { |key| key.to_s[OVERFLOW, 1].to_i }.map { |key| bags[key] }
    end

    # The bags to try for an item, in order: its type's, the default, the
    # overflow. A bag not set is nil, so the caller can tell which is missing.
    #
    # @param item [GameObj]
    # @return [Array<GameObj, nil>]
    def route(item) = [bags[item.type.to_s.to_sym], bags[:default], *overflow]

    # @param bag [GameObj, nil]
    # @return [Boolean]
    def full?(bag) = !bag.nil? && @full.key?(bag.name)

    # The bags loot is about to go into, to open before looting: the
    # default, the overflow, and each item's type bag.
    #
    # @param items [Array<GameObj>]
    # @return [Array<GameObj>]
    def bags_for(items)
      [bags[:default], *overflow, *items.map { |item| bags[item.type.to_s.to_sym] }].compact.uniq(&:id)
    end

    # Note that a bag was opened, or seen open, just now.
    #
    # @param bag [GameObj, nil]
    # @return [void]
    def opened(bag)
      @opened[bag.id] = Time.now if bag
    end

    # Note that the script closed a bag itself, so finding it closed says nothing.
    #
    # @param bag [GameObj, nil]
    # @return [void]
    def closed(bag)
      @opened.delete(bag.id) if bag
    end

    # A bag that closes itself, asked when it has just answered closed.
    # Without Lich's inventory feed: Lich still lists it among the containers
    # with its contents, which a bag closed by hand drops. Under the feed
    # every carried bag stays listed, closed or not, so that says nothing;
    # there it is a bag this script opened, or saw open, in the last minute
    # and did not close.
    #
    # @param bag [GameObj]
    # @return [Boolean]
    def closes_itself?(bag)
      return false if bag.nil?
      return GameObj.containers.key?(bag.id) && bag.contents.is_a?(Array) unless Containers.feed?

      at = @opened[bag.id]
      !at.nil? && Time.now - at <= JUST_OPENED
    end

    # Tell +learned+ something found out outside a put (a bag found closed
    # before looting, say).
    #
    # @param kind [Symbol] :auto_close, :crumbly or :unlootable
    # @param obj [GameObj]
    # @return [void]
    def learn(kind, obj) = @learned.call(kind, obj)

    # Put an item in one bag. A full bag is remembered (not for a gold
    # ingot, which eloot sells instead); a bag that closed itself, a
    # crumbly item and an unlootable one are told to +learned+.
    #
    # @param bag [GameObj]
    # @param item [GameObj]
    # @param loose [Boolean] see Hands.store (a skinning tool)
    # @return [Symbol] :stored, :full, :not_yours, :unlootable or :crumbled
    #   (both gone from the hand), :no_room (too heavy for what the bag has
    #   left, not tried), or what else Hands.store answered
    def put(bag, item, loose: false)
      return :no_room unless fits?(bag, item)

      # Hands.store opens it for the put, so it counts as opened from here
      closed = lambda do |closed_bag|
        learn(:auto_close, closed_bag) if closes_itself?(closed_bag)
        opened(closed_bag)
      end
      result = Hands.store(bag, item, loose: loose, on_closed: closed)
      @added[bag.id] += weight_of(item).to_i if %i[stored gone].include?(result)
      case result
      when :gone then :stored
      when :full
        @full[bag.name] = [Time.now.strftime('%Y-%m-%d %H:%M:%S'), Room.current.id, "#{item.name}(#{item.id})"] unless item.name =~ /gold ingot/
        :full
      when :unlootable, :crumbled
        @learned.call(result == :crumbled ? :crumbly : :unlootable, item)
        result
      else result
      end
    end

    # Put an item in the first bag along its route that takes it, skipping
    # the full ones.
    #
    # @param item [GameObj]
    # @param skipped [Proc, nil] given the route index of a bag not set
    # @return [GameObj, nil] the bag it went into, nil when none took it
    def store(item, skipped: nil)
      route(item).each_with_index do |bag, index|
        wait_while { stunned? } if stunned?
        if bag.nil?
          skipped&.call(index)
          next
        end
        next if full?(bag)
        return bag if %i[stored unlootable crumbled].include?(put(bag, item))
      end
      nil
    end

    # When no bag on an item's route has the room: move a box out of one of
    # them into another carried container with room for it, so the item
    # fits. Moving a box costs no roundtime.
    #
    # @param item [GameObj]
    # @return [GameObj, nil] the bag now with room, nil when nothing could be moved
    def make_room(item)
      weight = weight_of(item)
      return nil unless weight && @snapshot

      route(item).compact.reject { |bag| full?(bag) }.each do |bag|
        short = weight - room_in(bag).to_f
        next unless short.positive?

        # the snapshot still lists a box this pass already moved out
        boxes = (@snapshot[bag.id]&.children || []).reject { |c| @moved.include?(c.id) }
        box = boxes.select { |c| c.type.to_s =~ /\bbox\b/ && c.total_weight >= short }.min_by(&:total_weight)
        next unless box

        target = containers.reject { |c| c.id == bag.id }.select { |c| room_in(c).to_f >= box.total_weight }.max_by { |c| room_in(c) }
        # the live objects: a snapshot's contents never change, so a put into one is never seen
        into = target && GameObj[target.id.to_s]
        moving = GameObj[box.id.to_s]
        next unless into && moving
        next unless Hands.store(into, moving, loose: false) == :stored

        @added[target.id] += box.total_weight
        @added[bag.id] -= box.total_weight
        @moved << box.id
        return bag
      end
      nil
    end

    # Whether the disk has room for a box: under its item limit (a box
    # counts at least one) and its 500 lbs. True when the snapshot does not
    # know the disk, so it is tried as before.
    #
    # @param disk [GameObj]
    # @param box [GameObj]
    # @param limit [Integer] the disk's item limit (Carry.disk_limit)
    # @return [Boolean]
    def disk_room?(disk, box, limit: Carry.disk_limit)
      known = @snapshot && @snapshot[disk.id]
      return true unless known

      held = known.total_weight + @added[disk.id]
      Carry.disk_items(known) < limit && held + weight_of(box).to_i <= Carry::DISK_POUNDS
    end

    # The worn containers the snapshot knows the room of.
    #
    # @api private
    def containers = @snapshot ? @snapshot.worn.select { |c| c.container? && c.space_left } : []
  end
end
