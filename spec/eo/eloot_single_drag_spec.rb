# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'

# What eloot does with the answer of libeo's pickup: Inventory.single_drag and
# the methods beside it live in eloot.lic, which cannot be loaded outside Lich,
# so the real methods are read from the file and run against stand-ins.
# The real methods, read from the file.
SINGLE_DRAG_SOURCES = begin
  names = %i[single_drag drag_failed single_drag_box single_loot]
  found = {}
  walk = lambda do |node|
    found[node.name] ||= node.slice if node.is_a?(Prism::DefNode) && names.include?(node.name)
    node.compact_child_nodes.each { |c| walk.call(c) if c }
  end
  walk.call(Prism.parse(File.read(File.expand_path('../../scripts/eloot.lic', __dir__))).value)
  found
end

RSpec.describe 'eloot Inventory.single_drag' do
  let(:thing) { Struct.new(:id, :name) }
  let(:item) { thing.new('9', 'blue ruby') }
  let(:said) { [] }
  let(:events) { [] }
  let(:answers) { [] }
  let(:in_hand) { [true] }
  let(:tags) { [] }
  let(:hands) { [] }
  let(:handled) { [] }
  let(:inventory) do
    spec = self
    mod = Module.new
    elo = Module.new
    log = events
    msgs = said
    held = in_hand
    elo.define_singleton_method(:msg) { |type: 'yellow', text: '', **| msgs << [type, text] }
    elo.define_singleton_method(:refuse_room_operation!) { |what| log << [:refuse, what] }
    elo.define_singleton_method(:in_hand?) { |_obj| held.first }
    elo.define_singleton_method(:reset_disk_full) { log << :reset_disk_full }
    store = Struct.new(:observed) { def observe(snapshot) = (self.observed = snapshot; nil) }.new(:weights)
    data = Struct.new(:sacks_full, :stow).new({ 'bag' => ['x'], 'bag2' => ['y'] }, store)
    elo.define_singleton_method(:data) { data }
    mod.const_set(:ELoot, elo)
    mod.const_set(:Inventory, mod)
    room = Struct.new(:id, :tags).new(100, tags)
    mod.const_set(:Room, Module.new { define_singleton_method(:current) { room } })
    mod.const_set(:GameObj, Module.new do
      define_singleton_method(:right_hand) { spec.hands[0] || Struct.new(:name).new('Empty') }
      define_singleton_method(:left_hand) { spec.hands[1] || Struct.new(:name).new('Empty') }
    end)
    ingots = handled
    mod.const_set(:Sell, Module.new { define_singleton_method(:handle_ingot) { |ingot| ingots << ingot; :handled } })
    script = Struct.new(:name, :vars) { define_method(:pause) { log << :pause; nil } }.new('eloot', ['x'])
    mod.const_set(:Script, Module.new { define_singleton_method(:current) { script } })
    mod.define_singleton_method(:exit) { raise SystemExit }
    asked = events
    queue = answers
    pick = Object.new
    pick.define_singleton_method(:drag) { |obj, phase:, room_made:| asked << [:drag, obj.name, phase, room_made]; queue.shift }
    pick.define_singleton_method(:drag_box) { |obj| asked << [:drag_box, obj.name]; :box }
    pick.define_singleton_method(:loot) { |obj| asked << [:loot, obj.name]; :looted }
    mod.define_singleton_method(:pickup) { pick }
    SINGLE_DRAG_SOURCES.each_value { |source| mod.module_eval(source) }
    mod
  end

  it 'says nothing and answers nil when the item was put away' do
    answers.push(:stored)
    expect(inventory.single_drag(item)).to be_nil
    expect(events).to eq([[:drag, 'blue ruby', true, false]])
    expect(said.reject { |type, _| type == 'debug' }).to be_empty
  end

  it 'hands the caller\'s phase and room_made flags on' do
    answers.push(nil)
    inventory.single_drag(item, false, room_made: true)
    expect(events).to eq([[:drag, 'blue ruby', false, true]])
  end

  it 'ends the script when no default bag is set' do
    answers.push(:no_default)
    expect { inventory.single_drag(item) }.to raise_error(SystemExit)
  end

  describe 'when nowhere has room' do
    before { answers.push(:no_room) }

    it 'tries again for itself once the player has made room, with what was full forgotten' do
      answers.push(:stored)
      inventory.single_drag(item)
      expect(events).to eq([[:drag, 'blue ruby', true, false], [:refuse, 'continue with full containers; make space and retry'],
                            :pause, :reset_disk_full, [:drag, 'blue ruby', true, false]])
      expect(inventory.const_get(:ELoot).data.sacks_full.keys).to eq(['last cleared'])
      expect(inventory.const_get(:ELoot).data.stow.observed).to be_nil
      expect(said.map(&:last)).to include(' Failed to store the blue ruby.', ' Pausing the script to handle it yourself',
                                          ' ;unpause eloot after addressing to continue!')
    end

    it 'lists the full bags when there are several' do
      answers.push(:stored)
      inventory.single_drag(item)
      expect(said).to include(['info', ' Sacks Full[bag]: ["x"]'], ['info', ' Sacks Full[bag2]: ["y"]'])
    end

    it 'does not drag again when the item left the hand while paused' do
      in_hand[0] = false
      expect(inventory.single_drag(item)).to be_nil
      expect(events.count { |e| e.is_a?(Array) && e.first == :drag }).to eq(1)
    end

    it 'answers :full without pausing when the caller asked to be told' do
      expect(inventory.single_drag(item, on_full: :signal)).to eq(:full)
      expect(events).not_to include(:pause)
    end

    it 'sells a gold ingot at a locksmith instead of pausing' do
      ingot = thing.new('5', 'gold ingot')
      hands << ingot
      tags << 'locksmith'
      expect(inventory.single_drag(item)).to eq(:handled)
      expect(handled).to eq([ingot])
      expect(events).not_to include(:pause)
    end

    it 'pauses for a gold ingot away from a locksmith' do
      hands << thing.new('5', 'gold ingot')
      answers.push(:stored)
      inventory.single_drag(item)
      expect(events).to include(:pause)
    end

    it 'goes no further when the room cleanup refuses the pause' do
      inventory.const_get(:ELoot).define_singleton_method(:refuse_room_operation!) { |_what| raise 'refused' }
      expect { inventory.single_drag(item) }.to raise_error('refused')
      expect(events).not_to include(:pause)
    end
  end

  it 'asks the pickup for a box in a disk, and for a loot' do
    expect(inventory.single_drag_box(item)).to eq(:box)
    expect(inventory.single_loot(item)).to eq(:looted)
  end
end
