# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/carry'
require_relative '../../scripts/eo/stow'

RSpec.describe EO::Stow do
  let(:obj) { Struct.new(:id, :name, :type, keyword_init: true) }
  let(:gems) { obj.new(id: '1', name: 'gem pouch') }
  let(:sack) { obj.new(id: '2', name: 'leather sack') }
  let(:first) { obj.new(id: '3', name: 'first cloak') }
  let(:second) { obj.new(id: '4', name: 'second cloak') }
  let(:ruby) { obj.new(id: '9', name: 'blue ruby', type: 'gem') }
  let(:rock) { obj.new(id: '8', name: 'rock', type: 'junk') }
  let(:learned) { [] }
  let(:stow) do
    described_class.new(bags: { gem: gems, default: sack, overflow_container_2: second, overflow_container: first },
                        learned: ->(kind, thing) { learned << [kind, thing.name] })
  end

  before do
    stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:id).new(100) } })
    stow.define_singleton_method(:stunned?) { false }
  end

  it 'routes an item to its type bag, the default, then the overflow in number order' do
    expect(stow.route(ruby)).to eq([gems, sack, first, second])
    expect(stow.route(rock)).to eq([nil, sack, first, second])
  end

  it 'lists the bags to open before looting once each' do
    expect(stow.bags_for([ruby, rock, ruby])).to eq([sack, first, second, gems])
  end

  it 'skips a full bag and remembers it' do
    answers = { '1' => :full, '2' => :full, '3' => :stored }
    allow(EO::Hands).to receive(:store) { |bag, _item, **| answers[bag.id] }

    expect(stow.store(ruby)).to eq(first)
    expect(stow.full.keys).to eq(['gem pouch', 'leather sack'])
    expect(stow.full?(gems)).to be(true)

    expect(stow.store(ruby)).to eq(first)
    expect(EO::Hands).to have_received(:store).with(gems, ruby, anything).once
  end

  it 'does not mark a bag full over a gold ingot' do
    allow(EO::Hands).to receive(:store).and_return(:full)
    stow.put(sack, obj.new(id: '7', name: 'gold ingot'))
    expect(stow.full).to be_empty
  end

  it 'tells the caller what a put taught it' do
    allow(EO::Hands).to receive(:store).and_return(:crumbled)
    expect(stow.store(rock)).to eq(sack)
    expect(learned).to eq([[:crumbly, 'rock']])
  end

  it 'reports a bag that closed itself while keeping its contents' do
    allow(EO::Hands).to receive(:store) { |bag, _item, on_closed:, **| on_closed.call(bag) && :stored }
    stub_const('GameObj', Class.new { define_singleton_method(:containers) { { '2' => [] } } })
    sack.define_singleton_method(:contents) { [] }
    stow.put(sack, rock)
    expect(learned).to eq([[:auto_close, 'leather sack']])
  end

  it 'tells which route slots are not set, and answers nil when nothing took it' do
    allow(EO::Hands).to receive(:store).and_return(:full)
    skipped = []
    expect(stow.store(rock, skipped: ->(index) { skipped << index })).to be_nil
    expect(skipped).to eq([0])
  end

  it 'tells a bag that closes itself from one closed by hand, and passes on what it learns' do
    allow(EO::Containers).to receive(:feed?).and_return(false)
    stub_const('GameObj', Class.new { define_singleton_method(:containers) { { '2' => [] } } })
    sack.define_singleton_method(:contents) { [] }
    first.define_singleton_method(:contents) { nil }
    expect(stow.closes_itself?(sack)).to be(true)
    expect(stow.closes_itself?(first)).to be(false)
    stow.learn(:auto_close, sack)
    expect(learned).to eq([[:auto_close, 'leather sack']])
  end

  describe 'under the inventory feed, where a closed bag stays listed' do
    before do
      allow(EO::Containers).to receive(:feed?).and_return(true)
      stub_const('GameObj', Class.new { define_singleton_method(:containers) { { '2' => [], '3' => [] } } })
      [sack, first].each { |bag| bag.define_singleton_method(:contents) { [] } }
    end

    it 'does not take a bag found closed for one that closes itself' do
      expect(stow.closes_itself?(sack)).to be(false)
    end

    it 'takes one for it when the script opened it within the minute and did not close it' do
      stow.opened(sack)
      expect(stow.closes_itself?(sack)).to be(true)
      stow.closed(sack)
      expect(stow.closes_itself?(sack)).to be(false)

      stow.opened(first)
      allow(Time).to receive(:now).and_return(Time.now + 61)
      expect(stow.closes_itself?(first)).to be(false)
    end

    it 'learns it on the second put: the first only opens the bag' do
      answers = [:closed_then_stored, :closed_then_stored]
      allow(EO::Hands).to receive(:store) do |bag, _item, on_closed:, **|
        on_closed.call(bag) if answers.shift
        :stored
      end
      stow.put(sack, rock)
      expect(learned).to be_empty
      stow.put(sack, rock)
      expect(learned).to eq([[:auto_close, 'leather sack']])
    end
  end

  describe 'weights from the inventory feed' do
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
    let(:third) { obj.new(id: '3', name: 'patchwork backpack') }
    let(:big) { obj.new(id: '50', name: 'silver chest', type: 'box') }

    before { stow.observe(snapshot) }

    it 'passes over a bag without the room, and counts what went in' do
      allow(EO::Hands).to receive(:store).and_return(:stored)
      expect(stow.put(gems, big)).to eq(:no_room)
      expect(EO::Hands).not_to have_received(:store)
      expect(stow.put(sack, ruby)).to eq(:stored)
      expect(stow.room_in(sack)).to eq(40)
    end

    it 'tries every put again once the pass is over and the snapshot handed back' do
      allow(EO::Hands).to receive(:store).and_return(:stored)
      stow.observe(nil)
      expect(stow.put(gems, big)).to eq(:stored)
    end

    it 'tries as before when a weight is unknown' do
      expect(stow.fits?(gems, obj.new(id: '77', name: 'unseen thing'))).to be(true)
      expect(stow.fits?(obj.new(id: '88', name: 'keyring'), big)).to be(true)
    end

    it 'moves a box out of a bag to make room, into the container with the most' do
      heavy = obj.new(id: '9', name: 'gold ingot', type: 'box')
      allow(stow).to receive(:weight_of).and_call_original
      allow(stow).to receive(:weight_of).with(heavy).and_return(60)
      allow(EO::Hands).to receive(:store).and_return(:stored)
      live = { '3' => third, '50' => big }
      stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| live[id] } })

      # the live bag and box, not the snapshot's: Hands.store checks the bag's contents
      expect(stow.make_room(heavy)).to eq(sack)
      expect(EO::Hands).to have_received(:store).with(third, big, loose: false)
      expect(stow.room_in(sack)).to eq(97)
    end

    context 'with a worn container the STOW list does not name' do
      let(:heavy) { obj.new(id: '9', name: 'gold ingot', type: 'box') }
      let(:kept) { feed.new(id: '5', space_left: 500, children: [], container?: true) }
      let(:moved) { [] }

      before do
        snapshot.items['5'] = kept
        snapshot.worn << kept
        allow(stow).to receive(:weight_of).and_call_original
        allow(stow).to receive(:weight_of).with(heavy).and_return(60)
        into = moved
        allow(EO::Hands).to receive(:store) { |bag, _box, **| into << bag.id && :stored }
        live = { '3' => third, '50' => big, '5' => obj.new(id: '5', name: 'belt pouch') }
        stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| live[id] } })
      end

      it 'does not put a box in it, though it has the most room' do
        expect(stow.make_room(heavy)).to eq(sack)
        expect(moved).to eq(['3'])
      end

      it 'moves nothing when it is the only one with room' do
        snapshot.items['3'].space_left = 10
        expect(stow.make_room(heavy)).to be_nil
        expect(moved).to be_empty
      end
    end

    it 'moves another box the next time, not the one already moved' do
      crate = feed.new(id: '51', total_weight: 40, type: 'box', children: [], opaque?: true)
      snapshot['2'].children << crate
      heavy = obj.new(id: '9', name: 'gold ingot', type: 'box')
      allow(stow).to receive(:weight_of).and_call_original
      allow(stow).to receive(:weight_of).with(heavy).and_return(60)
      moved = []
      allow(EO::Hands).to receive(:store) { |_bag, box, **| moved << box.id && :stored }
      live = { '3' => third, '50' => big, '51' => obj.new(id: '51', name: 'iron crate', type: 'box') }
      stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| live[id] } })

      stow.make_room(heavy)
      allow(stow).to receive(:weight_of).with(heavy).and_return(120)
      expect(stow.make_room(heavy)).to eq(sack)
      expect(moved).to eq(%w[51 50])
    end

    it 'counts nothing moved when the box did not go in' do
      heavy = obj.new(id: '9', name: 'gold ingot', type: 'box')
      allow(stow).to receive(:weight_of).and_call_original
      allow(stow).to receive(:weight_of).with(heavy).and_return(60)
      allow(EO::Hands).to receive(:store).and_return(:gone)
      live = { '3' => third, '50' => big }
      stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| live[id] } })

      expect(stow.make_room(heavy)).to be_nil
      expect(stow.room_in(sack)).to eq(40)
      expect(stow.room_in(third)).to eq(100)
    end

    it 'tells a disk full by its count or its 500 lbs' do
      inside = Array.new(7) { feed.new(children: [], opaque?: false) }
      disk = feed.new(id: '60', total_weight: 100, children: inside)
      snapshot.items['60'] = disk
      disk_obj = obj.new(id: '60', name: 'Nisugi disk')
      expect(stow.disk_room?(disk_obj, big, limit: 8)).to be(true)
      inside << chest
      expect(stow.disk_room?(disk_obj, big, limit: 8)).to be(false)
      expect(stow.disk_room?(disk_obj, big, limit: 9)).to be(true)
      disk.total_weight = 460
      expect(stow.disk_room?(disk_obj, big, limit: 20)).to be(false)
    end
  end
end
