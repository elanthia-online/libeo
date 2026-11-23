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

    # A box put on a disk that the snapshot did not weigh.
    Box = Struct.new(:id, :total_weight, :type)

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
      @count = Hash.new(0)
      @at = {}
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
      @count = Hash.new(0)
      # where each box this pass moved or put on a disk is now, and the box
      @at = {}
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
      if %i[stored gone].include?(result)
        @added[bag.id] += weight_of(item).to_i
        @count[bag.id] += 1
      end
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
    # them so the item fits. The heaviest box goes into the disk, when there
    # is one; else a box goes into another box or overflow bag with room for
    # it. Moving a box costs no roundtime.
    #
    # @param item [GameObj] in a hand or still on the floor
    # @param disk [GameObj, nil] the character's own disk
    # @param full [Boolean] the disk has refused a box: its lightest comes out first
    # @return [GameObj, nil] the bag now with room, nil when nothing could be moved
    def make_room(item, disk: nil, full: false)
      weight = weight_of(item)
      return nil unless weight && @snapshot

      # boxes are shuffled between the box bag and the overflow bags only: one
      # in any other bag was not put there by a looting pass, and moving it
      # would use up room kept for boxes
      shuffled = [bags[:box], *overflow].compact
      route(item).compact.select { |bag| shuffled.any? { |s| s.id == bag.id } }.reject { |bag| full?(bag) }.each do |bag|
        short = weight - room_in(bag).to_f
        next unless short.positive?

        # the snapshot still lists a box this pass already moved out
        boxes = boxes_in(bag)
        return bag if disk && heaviest_to_disk(bag, boxes, short, disk, full, shuffled)

        box = boxes.select { |c| c.total_weight >= short }.min_by(&:total_weight)
        next unless box

        target = homes(shuffled, box).reject { |c| c.id == bag.id }.max_by { |c| room_in(c) }
        return bag if target && move(box, bag, target)
      end
      nil
    end

    # @param disk [GameObj]
    # @return [Integer] the boxes on a disk, with what this pass moved or
    #   put there; 0 for one the snapshot does not know
    def boxes_on(disk) = @snapshot && @snapshot[disk.id] ? boxes_in(disk).size : 0

    # @param disk [GameObj]
    # @return [Array<Numeric>, nil] the weight of each box on a disk, with
    #   what this pass moved or put there; nil for one the snapshot does not know
    def box_weights(disk) = @snapshot && @snapshot[disk.id] ? boxes_in(disk).map(&:total_weight) : nil

    # Count a box put on a disk, so the next one sees it there.
    #
    # @param disk [GameObj]
    # @param box [GameObj]
    # @return [void]
    def placed(disk, box)
      @added[disk.id] += weight_of(box).to_i
      @count[disk.id] += 1
      @at[box.id.to_s] = [disk.id.to_s, @snapshot&.[](box.id) || Box.new(box.id.to_s, 0, 'box')]
    end

    # Make a disk's slot for a box when every disk is full: the
    # disks keep the heaviest boxes. Of the disks with a box lighter than this
    # one, the one with the lightest gives it up, to the box or overflow bag
    # with the most room; a disk is any the box may go on, a group member's
    # too.
    #
    # @param box [GameObj] on the floor or in a hand
    # @param disks [Array<GameObj>] the disks it may go on
    # @return [GameObj, nil] the disk with the slot now, nil when no swap is worth it
    def disk_slot(box, disks)
      weight = weight_of(box)
      return nil unless weight && @snapshot

      lighter = disks.filter_map do |disk|
        known = @snapshot[disk.id]
        next unless known

        light = boxes_in(disk).min_by(&:total_weight)
        next unless light && light.total_weight < weight

        [disk, light]
      end
      lighter.sort_by { |_, light| light.total_weight }.each do |disk, light|
        home = homes([bags[:box], *overflow].compact, light).max_by { |c| room_in(c) }
        return disk if home && move(light, disk, home)
      end
      nil
    end

    # The worn containers the snapshot knows the room of.
    #
    # @api private
    def containers = @snapshot ? @snapshot.worn.select { |c| c.container? && c.space_left } : []

    private

    # The boxes in a container: what the snapshot lists, less the ones this
    # pass moved out, and those it moved or put in.
    def boxes_in(container)
      listed = (@snapshot[container.id]&.children || []).select { |c| c.type.to_s =~ /\bbox\b/ }.reject { |c| @at.key?(c.id.to_s) }
      listed + @at.values.select { |at, _| at == container.id.to_s }.map(&:last)
    end

    # The box and overflow bags with room for a box; a container kept for
    # something else is never filled.
    def homes(shuffled, box)
      allowed = shuffled.map { |c| c.id.to_s }
      containers.select { |c| allowed.include?(c.id.to_s) && room_in(c).to_f >= box.total_weight }
    end

    # The heaviest box of a bag into the disk. How many boxes a disk takes
    # is not known ahead (a locked box hides its item count), so a disk is
    # full once it has refused one: its lightest box then comes out first,
    # into the box or overflow bag with the most room.
    #
    # @return [Boolean] whether the bag now has +short+ pounds more
    def heaviest_to_disk(bag, boxes, short, disk, full, shuffled)
      heavy = boxes.max_by(&:total_weight)
      return false unless heavy

      if full
        light = boxes_in(disk).min_by(&:total_weight)
        return false unless light && light.total_weight < heavy.total_weight

        home = homes(shuffled, light).max_by { |c| room_in(c) }
        return false unless home
        return false if heavy.total_weight - (home.id.to_s == bag.id.to_s ? light.total_weight : 0) < short
        return false unless move(light, disk, home)
      elsif heavy.total_weight < short
        return false
      end
      move(heavy, bag, disk)
    end

    # Move a box between two containers and count it.
    #
    # @return [Boolean] whether it went in
    def move(box, from, to)
      # the live objects: a snapshot's contents never change, so a put into one is never seen
      into = GameObj[to.id.to_s]
      moving = GameObj[box.id.to_s]
      return false unless into && moving
      return false unless Hands.store(into, moving, loose: false) == :stored

      @added[to.id] += box.total_weight
      @added[from.id] -= box.total_weight
      @count[to.id] += 1
      @count[from.id] -= 1
      @at[box.id.to_s] = [to.id.to_s, box]
      true
    end
  end
end
