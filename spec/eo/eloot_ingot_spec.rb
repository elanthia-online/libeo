# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'

# These methods live in eloot.lic, which cannot be loaded outside Lich. The
# real ones are read from the file and run against a simulated pair of hands,
# gemshop and bank.
module ElootIngotSpec
  SOURCE = File.read(File.expand_path('../../scripts/eloot.lic', __dir__))
  TREE = Prism.parse(SOURCE).value

  def self.method_source(name)
    found = nil
    walk = lambda do |node|
      found ||= node if node.is_a?(Prism::DefNode) && node.name == name
      node.compact_child_nodes.each { |c| walk.call(c) if c }
    end
    walk.call(TREE)
    found.slice
  end

  Thing = Struct.new(:id, :name, :noun)
end

RSpec.describe 'eloot and a gold ingot that will not fit' do
  let(:thing) { ElootIngotSpec::Thing }
  let(:empty) { thing.new(nil, 'Empty', nil) }
  let(:box) { thing.new('90', 'iron chest', 'chest') }
  let(:stuck) { thing.new('1', 'gold ingot', 'ingot') }
  let(:hands) { { right: stuck, left: box } }
  let(:log) { [] }
  let(:refused) { [] }
  let(:ignored) { [] }
  let(:sack) do
    thing.new('50', 'gem pouch', 'pouch')
  end
  let(:stored) { [thing.new('2', 'gold ingot', 'ingot'), thing.new('3', 'blue ruby', 'ruby'), thing.new('4', 'gold ingot', 'ingot')] }
  let(:eloot) do
    spec = self
    mod = Module.new
    data = Struct.new(:silver_breakdown, :sell_exclude_regex, :put_regex).new(Hash.new(0), /dull/, /put/)
    mod.define_singleton_method(:data) { data }
    mod.define_singleton_method(:go2) { |place| spec.log << [:go2, place] }
    mod.define_singleton_method(:silver_check) { 0 }
    mod.define_singleton_method(:in_hand?) { |obj| spec.hands.values.any? { |h| h.id && h.id == obj.id } }
    mod.define_singleton_method(:silver_deposit) { |*args, **kw| spec.log << [:deposit, args, kw] }
    mod.define_singleton_method(:set_selling_containers) { |type:| type == 'gem' ? [spec.sack] : [] }
    mod.define_singleton_method(:fresh_contents) { |_sack| spec.stored }
    mod.define_singleton_method(:get_command) do |command, *_rest, **|
      spec.log << [:command, command]
      spec.hands.each { |side, held| spec.hands[side] = spec.empty if command.include?("##{held.id} ") }
    end
    gobj = Module.new
    gobj.define_singleton_method(:right_hand) { spec.hands[:right] }
    gobj.define_singleton_method(:left_hand) { spec.hands[:left] }
    inventory = Module.new
    inventory.define_singleton_method(:drag) do |item|
      side = spec.hands.find { |_, held| held.id.nil? }&.first
      spec.hands[side] = item
      spec.log << [:drag, item.id]
      true
    end
    inventory.define_singleton_method(:single_drag) { |item| spec.log << [:stow, item.name] }
    sell = Module.new
    sell.define_singleton_method(:selling_type?) { |_obj| true }
    sell.define_singleton_method(:sell_item) do |item, place, _data|
      spec.log << [:sell, item.id, place]
      next if spec.refused.include?(item.id)

      spec.hands.each { |side, held| spec.hands[side] = spec.empty if held.id == item.id }
    end
    mod.const_set(:Room, Module.new { define_singleton_method(:current) { Struct.new(:id).new(700) } })
    mod.const_set(:GameObj, gobj)
    mod.const_set(:Inventory, inventory)
    mod.const_set(:Sell, sell)
    mod.const_set(:ELoot, mod)
    # a method read in as text sees only its own module's constants
    %i[Room GameObj Inventory ELoot].each { |name| sell.const_set(name, mod.const_get(name)) }
    sell.const_set(:Sell, sell)
    %i[handle_ingot sell_stored_ingots sell_stored_ingot stow_held_note].each do |name|
      sell.module_eval(ElootIngotSpec.method_source(name))
    end
    mod
  end

  around do |example|
    was = $sell_ignore
    $sell_ignore = ignored
    example.run
    $sell_ignore = was
  end

  it 'sells the stored ingots in the same gemshop trip, banks without the coin hand, and goes back' do
    eloot::Sell.handle_ingot(stuck)
    expect(log).to eq([[:go2, 'gemshop'], [:sell, '1', 'Gemshop'],
                       [:drag, '2'], [:sell, '2', 'Gemshop'], [:drag, '4'], [:sell, '4', 'Gemshop'],
                       [:deposit, [], { keep_hands: true }], [:go2, 700]])
  end

  it 'never lets go of the box being looted' do
    eloot::Sell.handle_ingot(stuck)
    expect(hands[:left]).to eq(box)
  end

  it 'leaves the stored ingots when the stuck one did not sell, since no hand is free' do
    refused << '1'
    eloot::Sell.handle_ingot(stuck)
    expect(log.map(&:first)).to eq(%i[go2 sell deposit go2])
  end

  it 'puts an ingot the dealer will not buy back, and stops there' do
    refused << '2'
    eloot::Sell.handle_ingot(stuck)
    expect(log).to include([:command, 'put #2 in #50'])
    expect(ignored).to eq(['2'])
    expect(log).not_to include([:drag, '4'])
  end

  it 'leaves out an ingot the sell excludes name, or one already set aside' do
    stored[0].name = 'dull gold ingot'
    ignored << '4'
    eloot::Sell.handle_ingot(stuck)
    expect(log.map(&:first)).to eq(%i[go2 sell deposit go2])
  end

  it 'stows a note the shop paid with' do
    hands[:right] = thing.new('7', 'promissory note', 'note')
    eloot::Sell.stow_held_note
    expect(log).to eq([[:stow, 'promissory note']])
  end
end

RSpec.describe 'eloot ELoot.silver_deposit' do
  def deposit(*args, **kw)
    calls = []
    mod = Module.new
    settings = { sell_keep_silver: 0, sell_share_silvers: false, sell_deposit_coinhand: false }
    data = Struct.new(:settings, :coin_hand).new(settings, nil)
    mod.define_singleton_method(:data) { data }
    mod.define_singleton_method(:refuse_room_operation!) { |_what| nil }
    mod.define_singleton_method(:msg) { |**| nil }
    mod.define_singleton_method(:silver_check) { 100 }
    mod.define_singleton_method(:use_coin_hand) { calls << :coin_hand }
    mod.define_singleton_method(:f2p?) { false }
    mod.define_singleton_method(:go2) { |_place| nil }
    default = Struct.new(:contents).new([])
    mod.const_set(:StowList, Module.new { define_singleton_method(:stow_list) { { default: default } } })
    eo = Module.new
    eo.const_set(:Town, Module.new { define_singleton_method(:keep_silver) { |**| :none } })
    mod.const_set(:EO, eo)
    mod.const_set(:ELoot, mod)
    mod.module_eval(ElootIngotSpec.method_source(:silver_deposit))
    mod.silver_deposit(*args, **kw)
    calls
  end

  it 'moves coins into the coin hand as before' do
    expect(deposit).to eq([:coin_hand])
  end

  it 'leaves the coin hand alone when the hands must be kept' do
    expect(deposit(keep_hands: true)).to be_empty
  end
end

RSpec.describe 'eloot.lic, by its source' do
  let(:source) { ElootIngotSpec::SOURCE }

  it 'banks coins found in a box without the coin hand, the box being in hand' do
    expect(ElootIngotSpec.method_source(:box_loot)).to include('ELoot.silver_deposit(keep_hands: true)')
    expect(ElootIngotSpec.method_source(:box_loot)).not_to match(/ELoot\.silver_deposit$/)
  end

  it 'takes a sack off the full list each time a shop buys out of it' do
    sales = source.scan(/dothistimeout\("sell \#\#\{sack\.id\}".*\n(?:.*\n){0,5}/)
    expect(sales.size).to eq(4)
    expect(sales).to all(include('ELoot.data.sacks_full.delete(sack.name)'))
  end

  it 'clears the full bags and disks before each sell trip of a pool recovery, not only after' do
    %i[pool_direct_sell_recovery pool_sell_recovery].each do |name|
      before = ElootIngotSpec.method_source(name).split('Sell.sell(skip_boxes: true)').first.lines.last(3).join
      expect(before).to include('ELoot.data.sacks_full = { "last cleared"').and include('ELoot.reset_disk_full')
    end
  end
end
