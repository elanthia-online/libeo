# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/items'
require_relative '../../scripts/eo/boxes'

RSpec.describe EO::Items do
  include_context 'a script lending helpers'

  let(:thing) { Struct.new(:id, :name, :type, :status, keyword_init: true) }
  let(:empty) { thing.new(id: nil, name: 'Empty') }
  let(:box) { thing.new(id: '5', name: 'iron chest', type: 'box') }
  let(:hands) { { right: box, left: empty } }
  let(:fputs) { [] }
  let(:spells) { Hash.new { |h, k| h[k] = { known: false, affordable: false, casts: [], answers: [] } } }

  before do
    held = hands
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
      define_singleton_method(:[]) { |id| held.values.find { |o| o.id == id } }
    end)
    book = spells
    stub_const('Spell', Class.new do
      define_singleton_method(:[]) do |num|
        entry = book[num]
        Class.new do
          define_method(:known?) { entry[:known] }
          define_method(:affordable?) { entry[:affordable] }
          define_method(:cast) { |arg| entry[:casts] << arg && entry[:answers].shift }
        end.new
      end
    end)
    log = fputs
    described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    described_class.define_singleton_method(:dothistimeout) { |cmd, *_| log << cmd }
    allow(described_class).to receive(:sleep)
  end

  after { %i[fput dothistimeout].each { |m| described_class.singleton_class.remove_method(m) } }

  describe '.toss' do
    it 'does not throw a marked item, and says it found it so' do
      answers['mark #5 status'] = ['The chest has been marked as unsellable.']
      told = []
      expect(described_class.toss(box, 'trash', on_marked: -> { told << :marked })).to eq(:marked)
      expect(told).to eq([:marked])
      expect(fputs).to be_empty
    end

    it 'throws it and waits out roundtime' do
      described_class.define_singleton_method(:fput) { |_cmd| nil }
      allow(EO).to receive(:settle) { hands[:right] = empty }
      expect(described_class.toss(box, 'trash')).to eq(:tossed)
    end

    it 'tries as often as told while it stays in hand, then keeps it' do
      expect(described_class.toss(box, 'drop', attempts: 4)).to eq(:kept)
      expect(fputs).to eq(['drop #5'] * 4)
      expect(sent.count(:wait)).to eq(4)
    end

    it 'watches the hand for a second instead when told to poll' do
      expect(described_class.toss(box, 'trash', poll: true)).to eq(:kept)
      expect(described_class).to have_received(:sleep).with(0.1).exactly(10).times
      expect(sent).not_to include(:wait)
    end
  end

  describe '.phase' do
    before { spells[704].merge!(known: true, affordable: true) }

    it 'casts 704 at a box, again while hindered' do
      spells[704][:answers] = ['[Spell Hindrance for full plate is 12%, you rolled 5]', 'You gesture.']
      described_class.phase(box)
      expect(spells[704][:casts]).to eq(['at #5'] * 2)
    end

    it 'leaves what is not a box, an enruned or mithril one, and a caster without the mana' do
      described_class.phase(thing.new(id: '6', name: 'ruby', type: 'gem'))
      described_class.phase(thing.new(id: '7', name: 'enruned mithril coffer', type: 'box'))
      spells[704][:affordable] = false
      described_class.phase(box)
      expect(spells[704][:casts]).to be_empty
    end
  end

  describe '.unphase' do
    it 'hands back a box that is not phased' do
      answers['look at #5'] = ['You see nothing unusual.']
      expect(described_class.unphase(box)).to equal(box)
      expect(fputs).to be_empty
    end

    it 'drops a phased one and finds the box in a hand' do
      answers['look at #5'] = ['You see the shifting form of an iron chest.']
      expect(described_class.unphase(box)).to equal(box)
      expect(fputs).to eq(['drop #5'])
      expect(sent).to eq(['look at #5', :wait, 'glance hands'])
    end
  end

  describe '.lift_curse' do
    let(:cursed) { thing.new(id: '8', name: 'black opal', type: 'gem,cursed') }
    let(:gauntlet) { thing.new(id: '3', name: 'eonake gauntlet') }

    it 'casts 315 when it is known and can be afforded' do
      spells[315].merge!(known: true, affordable: true)
      expect(described_class.lift_curse(cursed)).to eq(:lifted)
      expect(spells[315][:casts]).to eq(['at #8'])
      expect(fputs).to be_empty
    end

    it 'tries a mana pulse first when it cannot, and says when that was not enough' do
      spells[315].merge!(known: true, affordable: false)
      expect(described_class.lift_curse(cursed, gauntlet: gauntlet)).to eq(:no_mana)
      expect(fputs).to eq(['mana pulse'])
    end

    it 'needs nothing done when the gauntlet is on the hand that is empty' do
      hands.replace(right: empty, left: box)
      answers['look #3'] = ['You are currently wearing the eonake gauntlet on your right hand.']
      expect(described_class.lift_curse(cursed, gauntlet: gauntlet)).to eq(:lifted)
      expect(sent).to eq(['look #3'])
    end

    it 'moves the gauntlet to the empty hand, swapping when it came off into the other' do
      hands.replace(right: empty, left: empty)
      answers['look #3'] = ['You are currently wearing the eonake gauntlet on your left hand.']
      expect(described_class.lift_curse(cursed, gauntlet: gauntlet)).to eq(:lifted)
      expect(sent).to eq(['look #3', 'remove #3', 'swap', 'wear #3'])
    end

    it 'cannot without 315 or a gauntlet' do
      expect(described_class.lift_curse(cursed)).to eq(:cannot)
    end
  end

  describe '.await_disk' do
    let(:disk) { thing.new(id: '40', name: 'Nisugi disk', status: nil) }
    let(:mine) { [] }

    before do
      found = mine
      stub_const('Disk', Class.new { define_singleton_method(:mine) { found.first } })
      hands[:left] = disk
    end

    it 'answers the disk at once when it is here' do
      mine << disk
      waits = []
      expect(described_class.await_disk(disk, on_wait: -> { waits << 1 })).to equal(disk)
      expect(waits).to be_empty
    end

    it 'says it is waiting, and gives up after five seconds' do
      waits = []
      expect(described_class.await_disk(disk, on_wait: -> { waits << 1 })).to be_nil
      expect(waits).to eq([1])
      expect(described_class).to have_received(:sleep).with(0.1).exactly(50).times
    end
  end
end

RSpec.describe EO::Boxes do
  include_context 'a script lending helpers'

  let(:box) { Struct.new(:id, :name, :contents).new('5', 'iron chest', []) }

  it 'opens a box and hands back what the game said' do
    answers['open #5'] = ['It appears to be locked.']
    expect(described_class.open(box)).to match(/locked/)
  end

  it 'looks in, on the screen or off it' do
    allow(EO).to receive(:command).and_return([])
    described_class.look_in(box)
    described_class.look_in(box, quiet: false)
    expect(EO).to have_received(:command).with('look in #5', EO::Containers::LOOK, silent: true, quiet: true).ordered
    expect(EO).to have_received(:command).with('look in #5', EO::Containers::LOOK, silent: false, quiet: false).ordered
  end

  it 'takes coins by GET, or by a coin charm when there is one' do
    answers['get coins from #5'] = ['You gather the remaining 250 coins.']
    expect(described_class.take_coins(box)).to match(described_class::COINS_DONE)
    described_class.take_coins(box, charm: Struct.new(:id).new('9'))
    expect(sent).to eq(['get coins from #5', 'point #9 at #5'])
  end

  it 'tells the two answers that mean no more silver can be carried' do
    expect('You can only collect 5 of the coins.').to match(described_class::COINS_FULL)
    expect('You cannot hold any more silvers.').to match(described_class::COINS_FULL)
  end

  it 'keeps an empty valuable box when boxes are sold, and a reliquary always' do
    silver = Struct.new(:name, :contents).new('silver strongbox', [])
    expect(described_class.keep?(silver, sell: true)).to be(true)
    expect(described_class.keep?(silver, sell: false)).to be(false)
    silver.contents << :ruby
    expect(described_class.keep?(silver, sell: true)).to be(false)
    expect(described_class.keep?(box, sell: true)).to be(false)
    expect(described_class.keep?(Struct.new(:name, :contents).new('ornate reliquary', [:bone]), sell: false)).to be(true)
  end
end
