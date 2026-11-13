# frozen_string_literal: true

module EO
  # Where an item goes by the STOW list: its type's bag, then the default,
  # then the overflow bags.
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
  end
end
