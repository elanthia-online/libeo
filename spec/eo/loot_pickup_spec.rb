# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/inventory/containers'
require_relative '../../scripts/eo/inventory/hands'
require_relative '../../scripts/eo/inventory/items'
require_relative '../../scripts/eo/inventory/boxes'
require_relative '../../scripts/eo/inventory/carry'
require_relative '../../scripts/eo/inventory/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/loot/context'
require_relative '../../scripts/eo/loot/pickup'

RSpec.describe EO::Loot::Pickup do
  let(:thing) { Struct.new(:id, :name, :type, :contents, keyword_init: true) }
  let(:gems) { thing.new(id: '1', name: 'gem pouch', contents: []) }
  let(:sack) { thing.new(id: '2', name: 'leather sack', contents: []) }
  let(:cloak) { thing.new(id: '3', name: 'first cloak', contents: []) }
  let(:cloak2) { thing.new(id: '4', name: 'second cloak', contents: []) }
  let(:ruby) { thing.new(id: '9', name: 'blue ruby', type: 'gem') }
  let(:chest) { thing.new(id: '50', name: 'silver chest', type: 'box') }
  let(:said) { [] }
  let(:floor) { [] }
  let(:loud) { said.reject { |type, _| type == 'debug' } }
  let(:settings) { { loot_phase: false, use_disk: false, use_disk_group: false } }
  let(:bags) { { gem: gems, default: sack, overflow_container: cloak } }
  let(:stow) { EO::Stow.new(bags: bags) }
  let(:stored) { [] }
  let(:full) { [] }
  let(:dragged) { [] }
  let(:opened) { [] }
  let(:hands) do
    log = stored
    refuse = full
    dragging = dragged
    opening = opened
    Class.new do
      define_method(:store_item) do |bag, item, _loose = false|
        log << [bag.name, item.name]
        !refuse.include?(bag.name)
      end
      define_method(:single_drag) { |item| dragging << item.name; :dragged }
      define_method(:open_single_container) { |bag| opening << bag.name }
    end.new
  end
  let(:commands) { [] }
  let(:answers) { [[]] }
  let(:waited) { [] }
  let(:inventory) { [] }
  let(:context) do
    said_to = said
    EO::Loot::Context.new(settings: settings, stow: stow, put_regex: /put/, say: ->(type:, text:) { said_to << [type, text] })
  end
  let(:pickup) do
    sent = commands
    replies = answers
    wait_log = waited
    inv = inventory
    described_class.new(context, hands: hands, command: ->(cmd, _regex) { sent << cmd; replies.shift || [] },
                                 inventory: -> { inv }, wait_for_disk: -> { wait_log << :disk })
  end

  before do
    stub_const('StowList', Module.new { define_singleton_method(:stow_list) { {} } })
    stub_const('Char', Module.new { define_singleton_method(:name) { 'Nisugi' } })
    on_floor = floor
    stub_const('GameObj', Module.new do
      define_singleton_method(:inv) { [] }
      define_singleton_method(:loot) { on_floor }
    end)
    allow(EO::Hands).to receive(:holding?).and_return(true)
    allow(EO::Items).to receive(:phase)
    pickup.define_singleton_method(:stunned?) { false }
    pickup.define_singleton_method(:sleep) { |_seconds| nil }
  end

  describe '#drag' do
    it 'puts an item in its type bag' do
      expect(pickup.drag(ruby)).to eq(:stored)
      expect(stored).to eq([['gem pouch', 'blue ruby']])
    end

    it 'goes on to the default and then the overflow bags when one does not take it' do
      full.push('gem pouch', 'leather sack')
      expect(pickup.drag(ruby)).to eq(:stored)
      expect(stored).to eq([['gem pouch', 'blue ruby'], ['leather sack', 'blue ruby'], ['first cloak', 'blue ruby']])
    end

    it 'does not try a bag known to be full' do
      stow.full['gem pouch'] = ['when', 1, 'x']
      pickup.drag(ruby)
      expect(stored).to eq([['leather sack', 'blue ruby']])
    end

    it 'skips an item type with no bag of its own without a word' do
      other = thing.new(id: '8', name: 'rock', type: 'junk')
      pickup.drag(other)
      expect(stored).to eq([['leather sack', 'rock']])
      expect(loud).to be_empty
    end

    it 'says so when an overflow bag is not set, and goes on' do
      stow.bags[:overflow_container] = nil
      stow.bags[:overflow_container_2] = cloak2
      full.push('gem pouch', 'leather sack')
      expect(pickup.drag(ruby)).to eq(:stored)
      expect(loud).to eq([['info', ' Skipping overflow container 1. No container identified.']])
      expect(stored.last).to eq(['second cloak', 'blue ruby'])
    end

    it 'answers :no_default, saying what to check, when there is no default bag' do
      stow.bags.delete(:default)
      full.push('gem pouch')
      expect(pickup.drag(ruby)).to eq(:no_default)
      expect(stored).to eq([['gem pouch', 'blue ruby']])
      expect(loud).to eq([['yellow', " No default container identified. This shouldn't happen."],
                          ['yellow', '   Check your STOW settings. Exiting']])
    end

    it 'answers :no_room when nowhere takes it, and does not move a box aside that is not there to move' do
      full.push('gem pouch', 'leather sack', 'first cloak')
      allow(stow).to receive(:make_room).and_return(nil)
      expect(pickup.drag(ruby)).to eq(:no_room)
      expect(stow).to have_received(:make_room).once
    end

    it 'moves a box aside to make room and tries again, once' do
      full.push('gem pouch', 'leather sack', 'first cloak')
      allow(stow).to receive(:make_room).and_return(sack)
      expect(pickup.drag(ruby)).to eq(:no_room)
      expect(stow).to have_received(:make_room).once
      expect(stored.size).to eq(6)
    end

    it 'stores it after the room is made' do
      refused = [full.push('gem pouch', 'leather sack', 'first cloak')]
      allow(stow).to receive(:make_room) { refused.first.clear; sack }
      expect(pickup.drag(ruby)).to eq(:stored)
    end

    it 'makes room for an item still on the floor, before it is picked up' do
      refused = [full.push('gem pouch', 'leather sack', 'first cloak')]
      floor << ruby
      allow(EO::Hands).to receive(:holding?).and_return(false)
      allow(stow).to receive(:make_room) { refused.first.clear; sack }
      expect(pickup.drag(ruby)).to eq(:stored)
      expect(stow).to have_received(:make_room).with(ruby, disk: nil, full: false)
    end

    it "hands over the character's own disk when disks are used" do
      full.push('gem pouch', 'leather sack', 'first cloak')
      settings[:use_disk] = true
      context.disk = thing.new(id: '60', name: 'Nisugi')
      allow(stow).to receive(:make_room).and_return(nil)
      pickup.drag(ruby)
      expect(stow).to have_received(:make_room).with(ruby, disk: context.disk, full: false)
    end

    it 'says so when that disk has refused a box' do
      full.push('gem pouch', 'leather sack', 'first cloak')
      settings[:use_disk] = true
      context.disk = thing.new(id: '60', name: 'Nisugi')
      context.disk_full = { 'Nisugi' => true }
      allow(stow).to receive(:make_room).and_return(nil)
      pickup.drag(ruby)
      expect(stow).to have_received(:make_room).with(ruby, disk: context.disk, full: true)
    end

    it 'does not make room for an item that is neither in hand nor on the floor' do
      full.push('gem pouch', 'leather sack', 'first cloak')
      allow(EO::Hands).to receive(:holding?).and_return(false)
      allow(stow).to receive(:make_room)
      expect(pickup.drag(ruby)).to eq(:no_room)
      expect(stow).not_to have_received(:make_room)
    end

    it 'puts a box in a disk before any bag, when disks are used' do
      settings[:use_disk] = true
      disk = thing.new(id: '60', name: 'Nisugi')
      context.disk = disk
      context.disk_full = { 'Nisugi' => false }
      allow(stow).to receive(:disk_slot).and_return(nil)
      allow(EO::Boxes).to receive(:disks).and_return([])
      allow(EO::Boxes).to receive(:to_disk) { |box, put:, **| put.call(disk, box) }
      expect(pickup.drag(chest)).to eq(:stored)
      expect(stored).to eq([['Nisugi', 'silver chest']])
    end

    it 'does nothing for an item that is Empty' do
      expect(pickup.drag(thing.new(id: '0', name: 'Empty', type: 'junk'))).to be_nil
      expect(stored).to be_empty
    end

    it 'waits out a stun between bags' do
      stuns = [true, false]
      pickup.define_singleton_method(:stunned?) { stuns.shift || false }
      pickup.define_singleton_method(:wait_while) { |&block| block.call }
      expect(pickup.drag(ruby)).to eq(:stored)
      expect(said).to include(['debug', 'single_drag: character stunned, waiting for it to clear'])
    end

    describe 'phasing' do
      before { settings[:loot_phase] = true }

      it 'phases a box once it is put away, when the settings say so' do
        pickup.drag(chest)
        expect(EO::Items).to have_received(:phase).with(chest)
      end

      it 'does not when the caller says not to, or the settings do not' do
        pickup.drag(chest, phase: false)
        settings[:loot_phase] = false
        pickup.drag(chest)
        expect(EO::Items).not_to have_received(:phase)
      end

      it 'does not phase what was not put away' do
        full.push('leather sack', 'first cloak')
        allow(stow).to receive(:make_room).and_return(nil)
        pickup.drag(chest)
        expect(EO::Items).not_to have_received(:phase)
      end
    end
  end

  describe '#drag_box' do
    let(:disk) { thing.new(id: '60', name: 'Nisugi') }
    let(:given) { [] }

    before do
      settings[:use_disk] = true
      context.disk = disk
      context.disk_full = { 'Nisugi' => false }
      allow(stow).to receive(:disk_slot).and_return(nil)
      allow(EO::Boxes).to receive(:disks).and_return([])
      allow(EO::Boxes).to receive(:to_disk) do |box, full:, put:, group: false|
        group_flag = group
        given << [box.name, full, group_flag]
        put.call(disk, box)
      end
    end

    context 'with a box on the floor' do
      let(:order) { [] }

      before do
        allow(EO::Hands).to receive(:holding?).and_return(false)
        allow(EO::Boxes).to receive(:disks).and_return([disk])
        live = { '60' => disk }
        stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| live[id] } })
        log = order
        allow(EO::Boxes).to receive(:to_disk) { |box, put:, **| log << :another && put.call(disk, box) }
      end

      it 'swaps with a lighter box on a disk before it is tried as one more, full or not' do
        allow(stow).to receive(:disk_slot).with(chest, [disk]) { order << :swap && disk }
        expect(pickup.drag_box(chest)).to be(true)
        expect(order).to eq([:swap])
        expect(stored).to eq([['Nisugi', 'silver chest']])
      end

      it 'is tried as one more box on the disk when none there is lighter' do
        allow(stow).to receive(:disk_slot) { order << :swap && nil }
        expect(pickup.drag_box(chest)).to be(true)
        expect(order).to eq(%i[swap another])
      end

      it 'goes to the bags when the disk refuses it after the swap, and is not tried again' do
        allow(stow).to receive(:disk_slot).and_return(disk)
        full << 'Nisugi'
        held = [false, true]
        allow(EO::Hands).to receive(:holding?) { held.shift }
        expect(pickup.drag_box(chest)).to be(false)
        expect(order).to be_empty
      end
    end

    it 'does not swap for a box already in hand, which leaves no hand for it' do
      allow(EO::Hands).to receive(:holding?).and_return(true)
      allow(stow).to receive(:disk_slot)
      expect(pickup.drag_box(chest)).to be(true)
      expect(stow).not_to have_received(:disk_slot)
    end

    it 'is false for what is not a box' do
      expect(pickup.drag_box(ruby)).to be(false)
      expect(EO::Boxes).not_to have_received(:to_disk)
    end

    it 'is false when no disk is used' do
      settings[:use_disk] = false
      expect(pickup.drag_box(chest)).to be(false)
    end

    it 'is false when every disk is known to be full and no swap is worth it' do
      context.disk_full = { 'Nisugi' => true }
      allow(EO::Hands).to receive(:holding?).and_return(false)
      expect(pickup.drag_box(chest)).to be(false)
      expect(EO::Boxes).not_to have_received(:to_disk)
    end

    it 'swaps a heavier box onto a disk known to be full, while the box is on the floor' do
      context.disk_full = { 'Nisugi' => true }
      allow(EO::Hands).to receive(:holding?).and_return(false)
      allow(EO::Boxes).to receive(:disks).and_return([disk])
      live = { '60' => disk }
      stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| live[id] } })
      allow(stow).to receive(:disk_slot).with(chest, [disk]).and_return(disk)
      expect(pickup.drag_box(chest)).to be(true)
      expect(stored).to eq([['Nisugi', 'silver chest']])
      expect(EO::Boxes).not_to have_received(:to_disk)
    end

    it 'does not try the disks when the character has none, or its own is full, and no group disks are used' do
      allow(EO::Hands).to receive(:holding?).and_return(false)
      context.disk = nil
      expect(pickup.drag_box(chest)).to be(false)
      context.disk = disk
      context.disk_full = { 'Nisugi' => true, 'Ann' => false }
      expect(pickup.drag_box(chest)).to be(false)
      expect(EO::Boxes).not_to have_received(:to_disk)
    end

    it 'waits for the disk, puts the box in, and says true' do
      expect(pickup.drag_box(chest)).to be(true)
      expect(waited).to eq([:disk])
      expect(stored).to eq([['Nisugi', 'silver chest']])
    end

    it 'does not wait when the character has no disk but group disks are used' do
      context.disk = nil
      settings[:use_disk_group] = true
      pickup.drag_box(chest)
      expect(waited).to be_empty
      expect(given.first[2]).to be(true)
    end

    it 'counts a box it put on a disk' do
      allow(stow).to receive(:placed)
      pickup.drag_box(chest)
      expect(stow).to have_received(:placed).with(disk, chest)
    end

    context 'when every disk is full' do
      let(:live) { { '60' => disk } }

      before do
        context.disk_full = { 'Nisugi' => true }
        # the box is still on the floor
        allow(EO::Hands).to receive(:holding?).and_return(false)
        allow(EO::Boxes).to receive(:disks).and_return([disk])
        objs = live
        stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| objs[id] } })
      end

      it 'puts a box on the disk a swap made a slot on, and counts it' do
        allow(stow).to receive(:disk_slot).with(chest, [disk]).and_return(disk)
        allow(stow).to receive(:placed)
        expect(pickup.drag_box(chest)).to be(true)
        expect(stored).to eq([['Nisugi', 'silver chest']])
        expect(stow).to have_received(:placed).with(disk, chest)
      end

      it 'goes on to the bags when no swap is worth it' do
        expect(pickup.drag_box(chest)).to be(false)
        expect(stored).to be_empty
        expect(loud).to be_empty
      end
    end

    it 'says a disk would not take it only when there are several to try' do
      full.push('Nisugi')
      context.disk_full = { 'Nisugi' => false, 'Ann' => false }
      pickup.drag_box(chest)
      expect(loud).to include(['info', " The #{chest} won't fit in the Nisugi disk. Trying a different disk."])
      context.disk_full = { 'Nisugi' => false }
      said.clear
      pickup.drag_box(chest)
      expect(said.map(&:last)).not_to include(" The #{chest} won't fit in the Nisugi disk. Trying a different disk.")
    end
  end

  describe '#loot' do
    let(:thing_in_hand) { thing.new(id: '9', name: 'blue ruby', type: 'gem') }
    let(:in_hand) { [true] }

    before do
      list = { gem: gems, default: sack }
      stub_const('StowList', Module.new { define_singleton_method(:stow_list) { list } })
      allow(EO::Hands).to receive(:holding?) { in_hand.first }
    end

    it 'takes it with LOOT and says true once it is in its bag' do
      in_hand[0] = false
      gems.contents << thing_in_hand
      expect(pickup.loot(thing_in_hand)).to be(true)
      expect(commands).to eq(['loot #9'])
    end

    it 'finds it in the default bag as well' do
      in_hand[0] = false
      sack.contents << thing_in_hand
      expect(pickup.loot(thing_in_hand)).to be(true)
    end

    it 'counts a skin gone from the hand as taken' do
      skin = thing.new(id: '7', name: 'boar skin', type: 'skin')
      in_hand[0] = false
      expect(pickup.loot(skin)).to be(true)
    end

    it 'drags it itself when its bag and the default are full' do
      stow.full['gem pouch'] = ['x']
      stow.full['leather sack'] = ['x']
      expect(pickup.loot(thing_in_hand)).to be_nil
      expect(dragged).to eq(['blue ruby'])
      expect(commands).to be_empty
    end

    it 'does nothing for no item' do
      expect(pickup.loot(nil)).to be_nil
      expect(commands).to be_empty
    end

    it 'opens a bag that closed itself, and learns it, when LOOT says it is closed' do
      in_hand[0] = false
      gems.contents << thing_in_hand
      closed = thing.new(id: '2', name: 'leather sack', contents: [])
      stub_const('GameObj', Module.new { define_singleton_method(:inv) { [closed] } })
      answers[0] = ['</inv>You can\'t put your <a exist="9" noun="ruby">blue ruby</a> in the <a exist="2" noun="sack">leather sack</a>.  It\'s closed!']
      allow(stow).to receive(:closes_itself?).and_return(true)
      allow(stow).to receive(:learn)
      pickup.loot(thing_in_hand)
      expect(stow).to have_received(:learn).with(:auto_close, closed)
      expect(opened).to eq(['leather sack'])
    end

    it 'keeps looking for it a few seconds before giving up on LOOT' do
      polls = 0
      allow(EO::Hands).to receive(:holding?) { (polls += 1) <= 9 }
      gems.contents << thing_in_hand
      slept = []
      pickup.define_singleton_method(:sleep) { |seconds| slept << seconds }
      expect(pickup.loot(thing_in_hand)).to be(true)
      expect(slept.size).to eq(3)
    end

    it 'accepts what the inventory shows when the treasure system put it elsewhere' do
      inventory << thing_in_hand
      expect(pickup.loot(thing_in_hand)).to be(true)
      expect(dragged).to be_empty
    end

    it 'drags it itself when it never arrived' do
      expect(pickup.loot(thing_in_hand)).to eq(:dragged)
      expect(dragged).to eq(['blue ruby'])
    end
  end
end
