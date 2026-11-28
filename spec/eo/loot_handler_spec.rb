# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/inventory/containers'
require_relative '../../scripts/eo/inventory/hands'
require_relative '../../scripts/eo/inventory/carry'
require_relative '../../scripts/eo/inventory/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/loot/context'
require_relative '../../scripts/eo/loot/pickup'
require_relative '../../scripts/eo/loot/handler'

RSpec.describe EO::Loot::Handler do
  let(:thing) do
    Struct.new(:id, :name, :type, keyword_init: true) do
      def empty? = false
    end
  end
  let(:sword) { thing.new(id: '1', name: 'rapier') }
  let(:gem) { thing.new(id: '2', name: 'blue ruby') }
  let(:none) { thing.new(id: nil, name: 'Empty') }
  let(:sack) { thing.new(id: '30', name: 'leather sack') }
  let(:cloak) { thing.new(id: '31', name: 'first cloak') }
  let(:said) { [] }
  let(:settings) { { favor_left: false, auto_close: [], keep_closed: true } }
  let(:stow) { EO::Stow.new(bags: { default: sack, overflow_container: cloak }) }
  let(:context) do
    said_to = said
    EO::Loot::Context.new(settings: settings, stow: stow, original_readylist: %i[weapon], say: ->(type:, text:) { said_to << [type, text] })
  end
  let(:stowed) { [] }
  let(:inventory) { [] }
  let(:due) { [] }
  let(:tool_records) { [] }
  let(:record) { { settled: false } }
  let(:handler) do
    stowing = stowed
    seen = inventory
    schedule = due
    described_class.new(context, command: ->(*, **) { [] }, inventory: -> { seen }, wait_for_disk: -> {},
                                 stow: ->(item) { stowing << item.name },
                                 on_tool_stow: ->(item, bag) { tool_records << [item.name, bag.name]; record },
                                 autoclosers_due: -> { schedule.empty? || schedule.shift })
  end
  let(:right_hand) { [none] }
  let(:left_hand) { [none] }
  let(:checks) { { right: true, left: true } }
  let(:game_obj) do
    held = { right: right_hand, left: left_hand }
    by_id = {}
    thing.tap do |klass|
      klass.define_singleton_method(:right_hand) { held[:right].first }
      klass.define_singleton_method(:left_hand) { held[:left].first }
      klass.define_singleton_method(:[]) { |id| by_id[id] }
      klass.define_singleton_method(:register) { |id, obj| by_id[id] = obj }
    end
  end

  before do
    stub_const('GameObj', game_obj)
    bags = { default: sack }
    stub_const('StowList', Module.new { define_singleton_method(:stow_list) { bags } })
    allow(EO::Hands).to receive(:ready_key).and_return(nil)
    allow(EO::Hands).to receive(:holding?).and_return(true)
    allow(EO::Hands).to receive(:stow_ready).and_return(false)
    allow(EO::Hands).to receive(:ready)
    allow(EO::Hands).to receive(:take).and_return(:held)
    allow(EO::Hands).to receive(:free_hand).and_return(:ok)
    allow(EO::Containers).to receive(:listed?).and_return(false)
    allow(EO::Containers).to receive(:closed?).and_return(true)
    allow(EO::Containers).to receive(:ensure_open).and_return(:opened)
    c = checks
    handler.define_singleton_method(:checkright) { c[:right] }
    handler.define_singleton_method(:checkleft) { c[:left] }
  end

  describe '#put_away' do
    it 'does nothing for no hand, or an empty one' do
      handler.put_away(nil)
      handler.put_away(none)
      expect(stowed).to be_empty
    end

    it 'puts a readied weapon back where it goes, and does not stow it' do
      allow(EO::Hands).to receive(:ready_key).with(sword, keys: %i[weapon]).and_return(:weapon)
      allow(EO::Hands).to receive(:stow_ready).with(:weapon, sword).and_return(true)
      handler.put_away(sword)
      expect(stowed).to be_empty
    end

    it 'puts anything else away with the caller\'s stow' do
      handler.put_away(gem)
      expect(stowed).to eq(['blue ruby'])
    end

    it 'stows a readied weapon the READY list could not take back' do
      allow(EO::Hands).to receive(:ready_key).and_return(:weapon)
      handler.put_away(sword)
      expect(stowed).to eq(['rapier'])
    end

    it 'does nothing for what has already left the hand' do
      allow(EO::Hands).to receive(:holding?).and_return(false)
      handler.put_away(gem)
      expect(stowed).to be_empty
    end
  end

  describe '#drag' do
    it 'does nothing for no item or an empty one' do
      expect(handler.drag(nil)).to be_nil
      expect(handler.drag(none)).to be_nil
      expect(EO::Hands).not_to have_received(:take)
    end

    it 'says true once it is held, handing the hand, the stow and the left-hand setting on' do
      settings[:favor_left] = true
      expect(handler.drag(gem, 'left')).to be(true)
      expect(EO::Hands).to have_received(:take).with(gem, to: :left, stow: kind_of(Proc), favor_left: true)
    end

    it 'says :crippled or :overloaded and does not end anything itself' do
      allow(EO::Hands).to receive(:take).and_return(:crippled)
      expect(handler.drag(gem)).to eq(:crippled)
      allow(EO::Hands).to receive(:take).and_return(:overloaded)
      expect(handler.drag(gem)).to eq(:overloaded)
    end

    it 'says false for anything else' do
      allow(EO::Hands).to receive(:take).and_return(:nothing)
      expect(handler.drag(gem)).to be(false)
    end

    describe 'an item that is not where it should be' do
      before do
        allow(EO::Hands).to receive(:take).with(gem, any_args).and_return(:missing)
        allow(handler).to receive(:open_single_container)
      end

      it 'looks in every bag, and drags it from where it is found' do
        inventory.push(sword, gem)
        allow(EO::Hands).to receive(:take).with(gem, any_args).and_return(:missing, :held)
        expect(handler.drag(gem, 'right')).to be(true)
        expect(handler).to have_received(:open_single_container).with(sack)
        expect(EO::Hands).not_to have_received(:take).with(sword, any_args)
      end

      it 'says it cannot find it when no bag has it' do
        expect(handler.drag(gem)).to be(false)
        expect(said.map(&:last)).to include(" Can't find blue ruby. Looked in all the bags in case it got misplaced.")
      end
    end
  end

  describe '#free_hand' do
    it 'says :crippled when neither hand is usable' do
      allow(EO::Hands).to receive(:free_hand).and_return(:crippled)
      expect(handler.free_hand).to eq(:crippled)
    end

    it 'says nothing otherwise, handing the left-hand setting on' do
      settings[:favor_left] = true
      expect(handler.free_hand).to be_nil
      expect(EO::Hands).to have_received(:free_hand).with(stow: kind_of(Proc), favor_left: true)
    end
  end

  describe '#free_hands' do
    before do
      right_hand[0] = sword
      left_hand[0] = gem
    end

    it 'puts away the hand asked for' do
      handler.free_hands(right: true)
      expect(stowed).to eq(['rapier'])
      stowed.clear
      handler.free_hands(left: true)
      expect(stowed).to eq(['blue ruby'])
    end

    it 'puts away both, and nothing for an empty hand' do
      handler.free_hands(both: true)
      expect(stowed).to eq(['rapier', 'blue ruby'])
      stowed.clear
      checks[:left] = false
      handler.free_hands(both: true)
      expect(stowed).to eq(['rapier'])
      stowed.clear
      checks.merge!(right: false, left: true)
      handler.free_hands(both: true)
      expect(stowed).to eq(['blue ruby'])
    end
  end

  describe '#open_single_container' do
    it 'does nothing for nothing' do
      handler.open_single_container(nil)
      expect(EO::Containers).not_to have_received(:ensure_open)
    end

    it 'opens a bag, notes it, and keeps it among the sell containers once' do
      allow(stow).to receive(:opened)
      handler.open_single_container(sack)
      handler.open_single_container(sack)
      expect(context.sell_containers).to eq([sack])
      expect(stow).to have_received(:opened).with(sack).twice
    end

    it 'finds a bag by its stow list key or by its id' do
      allow(stow).to receive(:opened)
      game_obj.register('99', cloak)
      handler.open_single_container('default')
      handler.open_single_container('99')
      expect(context.sell_containers).to eq([sack, cloak])
    end

    it 'says so, and opens nothing, for a bag it cannot place' do
      handler.open_single_container('nowhere')
      expect(EO::Containers).not_to have_received(:ensure_open)
      expect(said.last.last).to match(/not able to determine proper GameObj lookup/)
    end

    it 'notes a bag that is already open and goes no further' do
      allow(EO::Containers).to receive(:listed?).and_return(true)
      allow(EO::Containers).to receive(:closed?).and_return(false)
      allow(stow).to receive(:opened)
      game_obj.register('99', cloak)
      handler.open_single_container('99')
      expect(stow).to have_received(:opened).with(cloak)
      expect(EO::Containers).not_to have_received(:ensure_open)
    end

    it 'does not note a bag whose state is unknown, or keep one with nothing in it' do
      allow(stow).to receive(:opened)
      game_obj.register('99', cloak)
      allow(EO::Containers).to receive(:ensure_open).and_return(:unknown)
      handler.open_single_container('99')
      expect(stow).not_to have_received(:opened)
      expect(context.sell_containers).to eq([cloak])

      context.sell_containers.clear
      allow(EO::Containers).to receive(:ensure_open).and_return(:nothing)
      handler.open_single_container('99')
      expect(stow).to have_received(:opened)
      expect(context.sell_containers).to be_empty
    end
  end

  describe '#store_item' do
    let(:put) { [] }

    before do
      log = put
      allow(stow).to receive(:put) { |bag, item, loose:| log << [bag.name, item.name, loose]; :stored }
    end

    it 'says whether the stow took it' do
      expect(handler.store_item(sack, gem)).to be(true)
      expect(put).to eq([['leather sack', 'blue ruby', false]])
      allow(stow).to receive(:put).and_return(:full)
      expect(handler.store_item(sack, gem)).to be(false)
      expect(said.last.last).to eq('sacks_full(leather sack) - item: ' + gem.inspect)
    end

    it 'counts an item that crumbled or cannot be picked up as put away' do
      allow(stow).to receive(:put).and_return(:crumbled)
      expect(handler.store_item(sack, gem)).to be(true)
      allow(stow).to receive(:put).and_return(:unlootable)
      expect(handler.store_item(sack, gem)).to be(true)
    end

    it 'does nothing for no item or an empty one' do
      expect(handler.store_item(sack, nil)).to be_nil
      expect(handler.store_item(sack, none)).to be_nil
      expect(put).to be_empty
    end

    it 'puts a skinning tool away loose, noting it first and settling the note once it left the hand' do
      allow(EO::Hands).to receive(:holding?).and_return(false)
      handler.store_item(sack, sword, true)
      expect(tool_records).to eq([['rapier', 'leather sack']])
      expect(put).to eq([['leather sack', 'rapier', true]])
      expect(record[:settled]).to be(true)
    end

    it 'leaves the note open while the tool is still in hand' do
      handler.store_item(sack, sword, true)
      expect(record[:settled]).to be(false)
    end

    it 'notes nothing for an ordinary item' do
      handler.store_item(sack, gem)
      expect(tool_records).to be_empty
    end
  end

  describe 'opening the bags loot goes into' do
    before { allow(handler).to receive(:open_single_container) }

    it 'opens the bags that close themselves' do
      settings[:auto_close] = %w[cloak pack]
      handler.check_auto_closer
      expect(handler).to have_received(:open_single_container).with('cloak')
      expect(handler).to have_received(:open_single_container).with('pack')
    end

    it 'opens the bags the items go into when bags are kept closed' do
      handler.open_loot_containers([gem])
      expect(handler).to have_received(:open_single_container).with(sack)
      expect(handler).to have_received(:open_single_container).with(cloak)
    end

    it 'opens nothing when bags are not kept closed' do
      settings[:keep_closed] = false
      handler.open_loot_containers([gem])
      expect(handler).not_to have_received(:open_single_container)
    end

    it 'looks at the bags that close themselves only when it is time to' do
      settings[:auto_close] = %w[cloak]
      settings[:keep_closed] = false
      due.push(false)
      handler.open_loot_containers([gem])
      expect(handler).not_to have_received(:open_single_container)
      due.push(true)
      handler.open_loot_containers([gem])
      expect(handler).to have_received(:open_single_container).with('cloak')
    end
  end

  describe '#return_hands' do
    let(:taken) { [] }
    let(:drag) { ->(item, side) { taken << [item.name, side] } }

    before do
      context.right_hand = sword
      context.left_hand = gem
      right_hand[0] = sword
      left_hand[0] = gem
    end

    it 'does nothing when each hand holds what it did' do
      handler.return_hands(drag: drag)
      expect(taken).to be_empty
    end

    it 'takes back what a hand held when it holds something else now' do
      right_hand[0] = none
      handler.return_hands(drag: drag)
      expect(taken).to eq([['rapier', 'right']])
      left_hand[0] = none
      taken.clear
      handler.return_hands(drag: drag)
      expect(taken).to eq([['rapier', 'right'], ['blue ruby', 'left']])
    end

    it 'does not take back from a hand that was empty' do
      context.right_hand = none
      right_hand[0] = gem
      handler.return_hands(drag: drag)
      expect(taken).to be_empty
    end

    it 'readies a weapon from the READY list instead of taking it' do
      allow(EO::Hands).to receive(:ready_key).with(sword, keys: %i[weapon]).and_return(:weapon)
      right_hand[0] = none
      handler.return_hands(drag: drag)
      expect(EO::Hands).to have_received(:ready).with(:weapon, sword)
      expect(taken).to be_empty
    end

    it 'looks at the left hand after the right is back, not before' do
      right_hand[0] = none
      left_hand[0] = none
      back = ->(item, side) { taken << [item.name, side]; left_hand[0] = gem if side == 'right' }
      handler.return_hands(drag: back)
      expect(taken).to eq([['rapier', 'right']])
    end

    it 'takes them with its own drag when none is given' do
      right_hand[0] = none
      handler.return_hands
      expect(EO::Hands).to have_received(:take).with(sword, to: :right, stow: kind_of(Proc), favor_left: false)
    end
  end

  describe 'putting an item away without a pause' do
    let(:pickup) { instance_double(EO::Loot::Pickup) }

    before { handler.instance_variable_set(:@pickup, pickup) }

    it 'says :full when nothing has room and :no_default when there is no default bag' do
      allow(pickup).to receive(:drag).and_return(:no_room, :no_default, :stored, nil)
      expect(handler.single_drag(gem)).to eq(:full)
      expect(handler.single_drag(gem)).to eq(:no_default)
      expect(handler.single_drag(gem)).to be_nil
      expect(handler.single_drag(gem)).to be_nil
    end

    it 'hands the flags on, and signals whatever it is told' do
      allow(pickup).to receive(:drag).and_return(:stored)
      handler.single_drag(gem, false, on_full: :pause, room_made: true)
      expect(pickup).to have_received(:drag).with(gem, phase: false, room_made: true)
    end

    it 'asks the pickup for a box in a disk and for a loot' do
      allow(pickup).to receive(:drag_box).and_return(true)
      allow(pickup).to receive(:loot).and_return(:looted)
      expect(handler.single_drag_box(gem)).to be(true)
      expect(handler.single_loot(gem)).to eq(:looted)
    end
  end
end
