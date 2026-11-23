# frozen_string_literal: true

module EO
  # Where an item goes by the STOW list: its type's bag, then the default,
  # then the overflow bags; and, by weight, whether a bag has the room for
  # it (Weights).
  module Stow
    module_function

    OVERFLOW = /overflow_container_?(\d*)$/

    # The overflow bags' keys in number order: overflow_container first,
    # then overflow_container_2 and on.
    #
    # @param list [Hash{Symbol => GameObj}] the STOW list
    # @return [Array<Symbol>]
    def overflow_keys(list = StowList.stow_list)
      list.keys.select { |key| key.to_s.start_with?('overflow_container') }.sort_by { |key| key.to_s.match(OVERFLOW)[1].to_i }
    end

    # The bags to try for an item, in order: its type's, the default, each
    # overflow bag. A bag not set is nil, so the caller can tell which is
    # missing by its place: 0 the type's, 1 the default, 2 and on the overflow.
    #
    # @param item [GameObj]
    # @param list [Hash{Symbol => GameObj}] the STOW list
    # @return [Array<GameObj, nil>]
    def route(item, list = StowList.stow_list)
      [list[item.type.to_sym], list[:default], *overflow_keys(list).map { |key| list[key] }]
    end

    # The bags loot is about to go into, in the order to open them: the
    # default, the overflow bags as the STOW list has them, then each item's
    # type bag once. A bag not set is nil; the default or an overflow bag
    # that is also a type's bag comes up twice.
    #
    # @param items [Array<GameObj>]
    # @param list [Hash{Symbol => GameObj}] the STOW list
    # @return [Array<GameObj, nil>]
    def bags_for(items, list = StowList.stow_list)
      overflow = list.keys.select { |key| key.to_s.start_with?('overflow_container') }.map { |key| list[key] }
      typed = items.map { |item| list[item.type.to_sym] }.compact.uniq(&:id)
      [list[:default], *overflow, *typed]
    end

    # What a looting pass knows by weight, from one snapshot of Lich's
    # inventory feed: what each item weighs (on the floor too, a locked box
    # with what it holds) and how much each bag can still take. What the
    # pass puts away is counted from there, so a bag without the room is
    # passed over before the put and not after it.
    #
    # One for each pass. The weights are only good for the pass: a bag
    # emptied since would still read as full.
    class Weights
      # @param snapshot [Lich::Common::Inventory::Snapshot]
      def initialize(snapshot)
        @snapshot = snapshot
        @added = Hash.new(0)
        @moved = []
      end

      # @param item [GameObj]
      # @return [Integer, nil] its weight, nil when the snapshot does not know it
      def weight_of(item)
        @snapshot[item.id]&.total_weight
      end

      # @param bag [GameObj]
      # @return [Float, nil] pounds the bag can still take, nil when unknown
      #   (a bag limited by count and not by weight, say)
      def room_in(bag)
        left = @snapshot[bag.id]&.space_left
        left && left - @added[bag.id]
      end

      # Whether a bag can take an item by weight; true when either is
      # unknown, so the put is tried.
      #
      # @param bag [GameObj]
      # @param item [GameObj]
      # @return [Boolean]
      def fits?(bag, item)
        weight = weight_of(item)
        room = room_in(bag)
        weight.nil? || room.nil? || weight <= room
      end

      # Count an item as put in a bag.
      #
      # @param bag [GameObj]
      # @param item [GameObj]
      # @return [void]
      def stored(bag, item)
        @added[bag.id] += weight_of(item).to_i
      end

      # When none of the bags has the room for an item: move a box out of
      # one of them into another worn container with room for it, so the
      # item fits. Moving a box costs no roundtime.
      #
      # @param item [GameObj]
      # @param bags [Array<GameObj>] the bags the item may go in, in order
      # @return [GameObj, nil] the bag now with room, nil when nothing could
      #   be moved
      def make_room(item, bags)
        weight = weight_of(item)
        return nil unless weight

        bags.compact.each do |bag|
          short = weight - room_in(bag).to_f
          next unless short.positive?

          # the snapshot still lists a box this pass already moved out
          boxes = (@snapshot[bag.id]&.children || []).reject { |c| @moved.include?(c.id) }
          box = boxes.select { |c| c.type.to_s =~ /\bbox\b/ && c.total_weight >= short }.min_by(&:total_weight)
          next unless box

          target = containers.reject { |c| c.id == bag.id }.select { |c| room_in(c).to_f >= box.total_weight }.max_by { |c| room_in(c) }
          # the live objects: a snapshot's contents never change, so a put
          # into one would never be seen
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

      # Whether a floating disk has room for a box: under its item limit
      # and its weight limit. True when the snapshot does not know the
      # disk, so the put is tried.
      #
      # @param disk [GameObj]
      # @param box [GameObj]
      # @param limit [Integer] the disk's item limit
      # @return [Boolean]
      def disk_room?(disk, box, limit: Carry.disk_limit)
        known = @snapshot[disk.id]
        return true unless known

        held = known.total_weight + @added[disk.id]
        Carry.disk_items(known) < limit && held + weight_of(box).to_i <= Carry::DISK_POUNDS
      end

      private

      # The worn containers the snapshot knows the room of.
      def containers = @snapshot.worn.select { |c| c.container? && c.space_left }
    end
  end
end
