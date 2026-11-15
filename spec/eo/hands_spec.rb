# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'

RSpec.describe EO::Hands do
  include_context 'a script lending helpers'

  let(:thing) { Struct.new(:id, :name, :contents) }
  let(:empty) { thing.new(nil, 'Empty', nil) }
  let(:ruby) { thing.new('9', 'blue ruby', nil) }
  let(:bag) { thing.new('7', 'leather sack', []) }
  let(:hands) { { right: empty, left: empty } }
  let(:worn) { [] }
  let(:injuries) { Hash.new(0) }

  before do
    held = hands
    inventory = worn
    hurt = injuries
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
      define_singleton_method(:inv) { inventory }
    end)
    %w[Wounds Scars].each do |kind|
      stub_const(kind, Class.new do
        %i[rightArm rightHand leftArm leftHand].each { |part| define_singleton_method(part) { hurt[[kind, part]] } }
      end)
    end
    allow(described_class).to receive(:sleep)
    described_class.define_singleton_method(:waitrt?) { nil }
  end

  after { described_class.singleton_class.remove_method(:waitrt?) }

  describe '.holding?' do
    it 'goes by the ids in the two hands' do
      hands[:left] = ruby
      expect(described_class.holding?(ruby)).to be(true)
      expect(described_class.holding?(bag)).to be(false)
    end

    it 'reads an object with no id as held while a hand is empty' do
      expect(described_class.holding?(thing.new(nil, 'a thing'))).to be(true)
    end
  end

  describe '.free_hand' do
    let(:emptied) { [] }
    let(:empty_it) { ->(side) { emptied << side } }

    before { hands.replace(right: ruby, left: bag) }

    it 'does nothing while a hand is empty and its arm usable' do
      hands[:left] = empty
      expect(described_class.free_hand(favor_left: false, empty: empty_it)).to eq(:free)
      expect(emptied).to be_empty
    end

    it 'empties the right, or the left when it is favoured' do
      described_class.free_hand(favor_left: false, empty: empty_it)
      described_class.free_hand(favor_left: true, empty: empty_it)
      expect(emptied).to eq(%i[right left])
    end

    it 'empties the left when the right arm is beyond use, favoured or not' do
      injuries[['Wounds', :rightArm]] = 3
      described_class.free_hand(favor_left: false, empty: empty_it)
      expect(emptied).to eq([:left])
    end

    it 'does not count an empty hand on an arm beyond use as free' do
      hands[:right] = empty
      injuries[['Scars', :rightHand]] = 3
      described_class.free_hand(favor_left: false, empty: empty_it)
      expect(emptied).to eq([:left])
    end
  end

  describe '.take' do
    it 'drags to the hand named and sees the item arrive' do
      allow(described_class).to receive(:sleep) { hands[:right] = ruby }
      expect(described_class.take(ruby, 'right')).to eq(:held)
      expect(sent).to eq(['_drag #9 right'])
    end

    it 'tells an item the game cannot find, at once' do
      answers['_drag #9 left'] = ['Get what?']
      expect(described_class.take(ruby, 'left')).to eq(:missing)
      expect(described_class).not_to have_received(:sleep)
    end

    it 'tells one too heavy to pick up' do
      answers['_drag #9 right'] = ['You are unable to handle the additional load.']
      expect(described_class.take(ruby, 'right')).to eq(:overloaded)
    end

    it 'waits five seconds in all on an answer that says neither, then fails' do
      answers['_drag #9 right'] = ['A kobold arrives.']
      expect(described_class.take(ruby, 'right')).to eq(:failed)
      expect(described_class).to have_received(:sleep).with(0.1).exactly(50).times
    end
  end

  describe '.wear' do
    before { hands[:right] = ruby }

    it 'is worn once it has left the hand and is among what is worn' do
      allow(described_class).to receive(:sleep) do
        hands[:right] = empty
        worn << ruby
      end
      expect(described_class.wear(ruby)).to eq(:worn)
      expect(sent).to eq(['_drag #9 wear'])
    end

    it 'is stuck when it stays in the hand' do
      answers['_drag #9 wear'] = ["You can't wear that."]
      expect(described_class.wear(ruby)).to eq(:stuck)
      expect(described_class).not_to have_received(:sleep)
    end

    it 'is unseen when it left the hand and never showed as worn' do
      allow(described_class).to receive(:sleep) { hands[:right] = empty }
      expect(described_class.wear(ruby)).to eq(:unseen)
    end
  end

  describe '.store' do
    before { hands[:right] = ruby }

    def put_lands
      allow(described_class).to receive(:sleep) do
        hands[:right] = empty
        bag.contents << ruby
      end
    end

    it 'drags the item to the bag and sees it there' do
      put_lands
      expect(described_class.store(bag, ruby)).to eq(:stored)
      expect(sent).to eq(['_drag #9 #7'])
    end

    it 'tells the caller of a closed bag, then opens it and drags again' do
      answers['_drag #9 #7'] = [["You can't put your ruby in the sack.  It's closed!"], ['You put a ruby in your sack.']]
      order = []
      allow(EO).to(receive(:result).and_wrap_original { |original, *args| order << args.first && original.call(*args) })
      put_lands
      expect(described_class.store(bag, ruby, on_closed: ->(closed) { order << [:closed, closed.id] })).to eq(:stored)
      expect(order).to eq([[:closed, '7'], 'open #7'])
      expect(sent).to eq(['_drag #9 #7', 'open #7', '_drag #9 #7'])
    end

    it 'names each answer that ends it' do
      {
        'Hey, that belongs to Soandso!'                              => :not_yours,
        'Get what?'                                                  => :gone,
        "You can't put something that you can't hold into the sack." => :unlootable,
        "Your ruby won't fit in the leather sack."                   => :full,
        'The ruby crumbles and decays away.'                         => :crumbled
      }.each do |line, outcome|
        answers['_drag #9 #7'] = [line]
        expect(described_class.store(bag, ruby)).to eq(outcome)
      end
    end

    it 'has the bag opened when its contents are not known, unless it shows none' do
      bag.contents = nil
      asked = []
      described_class.store(bag, ruby, ensure_open: ->(b) { asked << b.id })
      described_class.store(bag, ruby, loose: true, ensure_open: ->(b) { asked << b.id })
      expect(asked).to eq(['7'] * 5)
    end

    it 'takes leaving the hand as proof for a bag that shows no contents' do
      allow(described_class).to receive(:sleep) { hands[:right] = empty }
      expect(described_class.store(bag, ruby, loose: true)).to eq(:stored)
    end

    it 'looks in a bag the game does not update before dragging again' do
      hands[:right] = empty
      allow(EO).to receive(:command).and_wrap_original do |original, *args, **opts|
        bag.contents << ruby if args.first == 'look in #7'
        original.call(*args, **opts)
      end
      expect(described_class.store(bag, ruby)).to eq(:stored)
      expect(sent).to eq(['_drag #9 #7', 'look in #7'])
    end

    it 'fails after five tries' do
      expect(described_class.store(bag, ruby)).to eq(:failed)
      expect(sent).to eq(['_drag #9 #7'] * 5)
    end
  end

  describe 'the READY list' do
    let(:sheath) { thing.new('3', 'sheath', []) }
    let(:ready) { { weapon: ruby, sheath: sheath } }
    let(:store_list) { { weapon: 'put in sheath' } }

    before do
      list = ready
      stores = store_list
      stub_const('ReadyList', Class.new do
        define_singleton_method(:ready_list) { list }
        define_singleton_method(:store_list) { stores }
      end)
      hands[:right] = ruby
    end

    it 'gives READY and STORE their words for the two keys that differ' do
      expect(described_class.ready_word('secondary_weapon')).to eq('2weapon')
      expect(described_class.ready_word('ranged_weapon')).to eq('ranged')
      expect(described_class.ready_word('shield')).to eq('shield')
    end

    it 'has the sheath seen to, then stores until the item leaves the hand' do
      opened = []
      tries = 0
      allow(described_class).to receive(:sleep) { hands[:right] = empty if (tries += 1) == 2 }
      expect(described_class.stow_ready(:weapon, ruby, ensure_open: ->(s) { opened << s.id })).to be(true)
      expect(opened).to eq(['3'])
      expect(sent).to eq(['store weapon'] * 2)
    end

    it 'gives up storing after ten tries' do
      expect(described_class.stow_ready(:weapon, ruby)).to be(false)
      expect(sent.size).to eq(10)
    end

    it 'readies until the item is in hand, and has nothing to do for an empty key' do
      hands[:right] = empty
      allow(described_class).to receive(:sleep) { hands[:right] = ruby }
      expect(described_class.return_ready('weapon', ruby)).to be(true)
      expect(sent).to eq(['ready weapon'])
      expect(described_class.return_ready(:shield, ruby)).to be(true)
      expect(described_class.stow_ready(:shield, ruby)).to be(true)
    end
  end
end
