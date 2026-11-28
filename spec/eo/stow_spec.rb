# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/inventory/containers'
require_relative '../../scripts/eo/inventory/hands'
require_relative '../../scripts/eo/inventory/carry'
require_relative '../../scripts/eo/inventory/stow'

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

    # the sack holds boxes here; the gem pouch is the default bag
    let(:stow) do
      described_class.new(bags: { box: sack, default: gems, overflow_container: first, overflow_container_2: second })
    end

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

      let(:live) { { '1' => gems, '2' => sack, '3' => third, '50' => big, '5' => obj.new(id: '5', name: 'belt pouch') } }

      before do
        table = live
        stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| table[id] } })
      end

      it 'does not put a box in the default bag, which has room, when no box or overflow bag does' do
        snapshot.items['1'].space_left = 500
        snapshot.items['2'].space_left = 0
        snapshot.items['3'].space_left = 10
        snapshot.items['3'].children = [feed.new(id: '50', total_weight: 57, type: 'box', children: [], opaque?: true)]
        expect(stow.make_room(heavy)).to be_nil
        expect(moved).to be_empty
      end

      it 'does not take a box out of the default bag, which eloot never put one in' do
        snapshot.items['1'].space_left = 5
        snapshot.items['1'].children = [feed.new(id: '50', total_weight: 57, type: 'box', children: [], opaque?: true)]
        snapshot.items['2'].children = []
        expect(stow.make_room(heavy)).to be_nil
        expect(moved).to be_empty
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

    context 'with a disk' do
      let(:heavy) { obj.new(id: '9', name: 'gold ingot', type: 'box') }
      let(:crate) { feed.new(id: '51', total_weight: 20, type: 'box', children: [], opaque?: true) }
      let(:disk) { obj.new(id: '60', name: 'Nisugi disk') }
      let(:moves) { [] }

      before do
        snapshot['2'].children << crate
        snapshot.items['60'] = feed.new(id: '60', total_weight: 0, children: [])
        allow(stow).to receive(:weight_of).and_call_original
        allow(stow).to receive(:weight_of).with(heavy).and_return(60)
        log = moves
        allow(EO::Hands).to receive(:store) { |bag, box, **| log << [bag.id, box.id] && :stored }
        live = { '3' => third, '50' => big, '60' => disk }
        %w[51 70 71].each { |id| live[id] = obj.new(id: id, name: 'iron crate', type: 'box') }
        stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| live[id] } })
      end

      def in_disk(*weights)
        weights.each_with_index.map { |w, i| feed.new(id: (70 + i).to_s, total_weight: w, type: 'box', children: [], opaque?: true) }
      end

      it 'puts the heaviest box in the disk, not the lightest that would do' do
        expect(stow.make_room(heavy, disk: disk)).to eq(sack)
        expect(moves).to eq([%w[60 50]])
        expect(stow.room_in(sack)).to eq(97)
      end

      it 'takes the lightest box out of a disk that refused one, and puts the heaviest in' do
        snapshot['60'].children = in_disk(30, 5)
        expect(stow.make_room(heavy, disk: disk, full: true)).to eq(sack)
        expect(moves).to eq([%w[3 71], %w[60 50]])
        expect(stow.room_in(third)).to eq(95)
      end

      it 'leaves a full disk alone when nothing in it is lighter, and moves a box to another bag' do
        snapshot['60'].children = in_disk(57, 80)
        expect(stow.make_room(heavy, disk: disk, full: true)).to eq(sack)
        expect(moves).to eq([%w[3 51]])
      end

      it 'leaves a full disk alone when its lightest box fits no box or overflow bag' do
        snapshot['60'].children = in_disk(30, 5)
        snapshot['2'].space_left = 4
        snapshot['3'].space_left = 4
        expect(stow.make_room(heavy, disk: disk, full: true)).to be_nil
        expect(moves).to be_empty
      end

      it 'goes to another bag when the disk refuses the box' do
        log = moves
        allow(EO::Hands).to receive(:store) { |bag, box, **| log << [bag.id, box.id] && (bag.id == '60' ? :full : :stored) }
        expect(stow.make_room(heavy, disk: disk)).to eq(sack)
        expect(moves).to eq([%w[60 50], %w[3 51]])
        expect(stow.room_in(sack)).to eq(60)
      end
    end

    describe '#disk_slot' do
      let(:ground) { obj.new(id: '9', name: 'iron strongbox', type: 'box') }
      let(:mine) { obj.new(id: '60', name: 'Nisugi disk') }
      let(:ann) { obj.new(id: '61', name: 'Ann disk') }
      let(:moves) { [] }
      let(:live) { { '3' => third, '2' => sack, '60' => mine, '61' => ann } }

      def boxes(*pairs) = pairs.map { |id, w| feed.new(id: id, total_weight: w, type: 'box', children: [], opaque?: true) }

      before do
        snapshot.items['60'] = feed.new(id: '60', total_weight: 35, children: boxes(['70', 5], ['71', 30]))
        snapshot.items['61'] = feed.new(id: '61', total_weight: 40, children: boxes(['72', 10], ['73', 30]))
        allow(stow).to receive(:weight_of).and_call_original
        allow(stow).to receive(:weight_of).with(ground).and_return(40)
        log = moves
        allow(EO::Hands).to receive(:store) { |bag, box, **| log << [box.id, bag.id] && :stored }
        %w[70 71 72 73 74].each { |id| live[id] = obj.new(id: id, name: 'crate', type: 'box') }
        table = live
        stub_const('GameObj', Module.new { define_singleton_method(:[]) { |id| table[id] } })
      end

      it 'takes the lightest box of all the disks out, into the box or overflow bag with the most room' do
        expect(stow.disk_slot(ground, [mine, ann])).to eq(mine)
        expect(moves).to eq([%w[70 3]])
        expect(stow.room_in(third)).to eq(95)
      end

      it 'takes it from a group member\'s disk when that one holds the lightest' do
        snapshot.items['60'].children = boxes(['70', 20], ['71', 30])
        expect(stow.disk_slot(ground, [mine, ann])).to eq(ann)
        expect(moves).to eq([%w[72 3]])
      end

      it 'swaps nothing when no box on a disk is lighter' do
        allow(stow).to receive(:weight_of).with(ground).and_return(5)
        expect(stow.disk_slot(ground, [mine, ann])).to be_nil
        expect(moves).to be_empty
      end

      it 'swaps nothing when the lighter box fits no box or overflow bag' do
        snapshot.items['2'].space_left = 4
        snapshot.items['3'].space_left = 4
        expect(stow.disk_slot(ground, [mine])).to be_nil
        expect(moves).to be_empty
      end

      it 'never takes a box from a disk it was not given (a stranger\'s), though the snapshot shows it' do
        snapshot.items['62'] = feed.new(id: '62', total_weight: 1, children: boxes(['75', 1]))
        live['62'] = obj.new(id: '62', name: 'Bob disk')
        live['75'] = obj.new(id: '75', name: 'crate', type: 'box')
        snapshot.items['60'].children = boxes(['70', 45], ['71', 50])
        expect(stow.disk_slot(ground, [mine])).to be_nil
        expect(moves).to be_empty
      end

      it 'leaves out a disk the snapshot does not know, though this pass put a box on it' do
        cy = obj.new(id: '63', name: 'Cy disk')
        live['63'] = cy
        small = obj.new(id: '74', name: 'tiny coffer', type: 'box')
        snapshot.items['74'] = feed.new(id: '74', total_weight: 2, type: 'box')
        stow.placed(cy, small)
        expect(stow.disk_slot(ground, [cy])).to be_nil
        expect(moves).to be_empty
      end

      it 'counts a box it put on a disk this pass, and swaps that one out when it is the lightest' do
        small = obj.new(id: '74', name: 'tiny coffer', type: 'box')
        snapshot.items['74'] = feed.new(id: '74', total_weight: 2, type: 'box')
        stow.placed(mine, small)
        expect(stow.disk_slot(ground, [mine])).to eq(mine)
        expect(moves).to eq([%w[74 3]])
      end

      it 'does not take a box out twice' do
        stow.disk_slot(ground, [mine])
        expect(stow.disk_slot(ground, [mine])).to eq(mine)
        expect(moves).to eq([%w[70 3], %w[71 3]])
      end

      it 'counts the boxes on a disk, with what this pass moved out or put on' do
        expect(stow.boxes_on(mine)).to eq(2)
        stow.disk_slot(ground, [mine])
        expect(stow.boxes_on(mine)).to eq(1)
        stow.placed(mine, ground)
        expect(stow.boxes_on(mine)).to eq(2)
        expect(stow.boxes_on(obj.new(id: '62', name: 'Bob disk'))).to eq(0)
      end
    end
  end
end
