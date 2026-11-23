# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/carry'
require_relative '../../scripts/eo/stow'

RSpec.describe EO::Stow::Weights do
  let(:obj) { Struct.new(:id, :name, :type, keyword_init: true) }
  # An inventory feed item: the weight, room and children Lich gives.
  let(:feed) { Struct.new(:id, :total_weight, :space_left, :children, :type, :opaque?, :container?, keyword_init: true) }
  let(:chest) { feed.new(id: '50', total_weight: 57, type: 'box', children: [], opaque?: true) }
  let(:snapshot) do
    items = {
      '9'  => feed.new(id: '9', total_weight: 0),
      '50' => chest,
      '1'  => feed.new(id: '1', space_left: 5, children: [], container?: true),
      '2'  => feed.new(id: '2', space_left: 40, children: [chest], container?: true),
      '3'  => feed.new(id: '3', space_left: 100, children: [], container?: true)
    }
    Struct.new(:items, :worn) { def [](id) = items[id] }.new(items, [items['1'], items['2'], items['3']])
  end
  let(:gems) { obj.new(id: '1', name: 'gem pouch') }
  let(:sack) { obj.new(id: '2', name: 'leather sack') }
  let(:third) { obj.new(id: '3', name: 'patchwork backpack') }
  let(:ruby) { obj.new(id: '9', name: 'blue ruby', type: 'gem') }
  let(:big) { obj.new(id: '50', name: 'silver chest', type: 'box') }
  let(:heavy) { obj.new(id: '9', name: 'gold ingot', type: 'box') }
  let(:weights) { described_class.new(snapshot) }

  it 'knows a bag without the room for an item, and counts what went in' do
    expect(weights.fits?(gems, big)).to be(false)
    expect(weights.fits?(third, big)).to be(true)
    weights.stored(third, big)
    expect(weights.room_in(third)).to eq(43)
    expect(weights.fits?(third, big)).to be(false)
  end

  it 'says an item fits when a weight is unknown, so the put is tried' do
    expect(weights.fits?(gems, obj.new(id: '77', name: 'unseen thing'))).to be(true)
    expect(weights.fits?(obj.new(id: '88', name: 'keyring'), big)).to be(true)
  end

  describe '#make_room' do
    let(:live) { { '3' => third, '50' => big } }

    before do
      things = live
      stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| things[id] } })
      allow(weights).to receive(:weight_of).and_call_original
      allow(weights).to receive(:weight_of).with(heavy).and_return(60)
    end

    it 'moves a box out of a bag, into the container with the most room' do
      allow(EO::Hands).to receive(:store).and_return(:stored)
      # the live bag and box, not the snapshot's: Hands.store checks the bag's contents
      expect(weights.make_room(heavy, [gems, sack])).to eq(sack)
      expect(EO::Hands).to have_received(:store).with(third, big, loose: false)
      expect(weights.room_in(sack)).to eq(97)
    end

    it 'moves another box the next time, not the one already moved' do
      snapshot['2'].children << feed.new(id: '51', total_weight: 40, type: 'box', children: [], opaque?: true)
      live['51'] = obj.new(id: '51', name: 'iron crate', type: 'box')
      moved = []
      allow(EO::Hands).to receive(:store) { |_bag, box, **| moved << box.id && :stored }

      weights.make_room(heavy, [sack])
      allow(weights).to receive(:weight_of).with(heavy).and_return(120)
      expect(weights.make_room(heavy, [sack])).to eq(sack)
      expect(moved).to eq(%w[51 50])
    end

    it 'counts nothing moved when the box did not go in' do
      allow(EO::Hands).to receive(:store).and_return(:gone)
      expect(weights.make_room(heavy, [sack])).to be_nil
      expect(weights.room_in(sack)).to eq(40)
      expect(weights.room_in(third)).to eq(100)
    end

    it 'has nothing to move for an item it does not know the weight of' do
      expect(weights.make_room(obj.new(id: '77', name: 'unseen thing'), [sack])).to be_nil
    end
  end

  it 'tells a disk full by its count or its 500 lbs' do
    inside = Array.new(7) { feed.new(children: [], opaque?: false) }
    disk = feed.new(id: '60', total_weight: 100, children: inside)
    snapshot.items['60'] = disk
    disk_obj = obj.new(id: '60', name: 'Nisugi disk')
    expect(weights.disk_room?(disk_obj, big, limit: 8)).to be(true)
    inside << chest
    expect(weights.disk_room?(disk_obj, big, limit: 8)).to be(false)
    expect(weights.disk_room?(disk_obj, big, limit: 9)).to be(true)
    disk.total_weight = 460
    expect(weights.disk_room?(disk_obj, big, limit: 20)).to be(false)
  end
end
