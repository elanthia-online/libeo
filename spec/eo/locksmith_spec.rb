# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/selling'
require_relative '../../scripts/eo/locksmith'

RSpec.describe EO::Selling do
  include_context 'a script lending helpers'

  let(:thing) { Struct.new(:id, :name) }
  let(:ruby) { thing.new('9', 'blue ruby') }
  let(:hands) { { right: ruby, left: thing.new(nil, 'Empty') } }

  before do
    held = hands
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
    end)
    allow(described_class).to receive(:sleep)
  end

  it 'offers an item and gives it two seconds to leave the hand' do
    answers['sell #9'] = ['You offer to sell your ruby.']
    expect(described_class.sell(ruby)).to eq(:offered)
    expect(described_class).to have_received(:sleep).with(0.1).exactly(20).times
  end

  it 'stops waiting once the hand is empty' do
    answers['sell #9'] = ['You ask the gemcutter.']
    allow(described_class).to receive(:sleep) { hands[:right] = hands[:left] }
    described_class.sell(ruby)
    expect(described_class).to have_received(:sleep).once
  end

  it 'tells a shop that will not take it, without waiting' do
    ["That's not quite my field.", 'What were you referring to?', "The company don't buy trash."].each do |line|
      answers['sell #9'] = [line]
      expect(described_class.sell(ruby)).to eq(:refused)
    end
    expect(described_class).not_to have_received(:sleep)
  end

  it 'reads the figure in an appraisal, in each of its wordings' do
    expect(described_class.worth(["I'll give you 1,250 silvers for it."])).to eq(raw: '1,250', amount: 1250)
    expect(described_class.worth("I'll offer you 300 for it if you want to sell.")).to eq(raw: '300', amount: 300)
    expect(described_class.worth(['He glances at it.'])).to be_nil
    answers['appraise #9'] = ['You ask the pawnbroker to appraise your ruby.']
    expect(described_class.appraise(ruby)).to eq(answers['appraise #9'])
  end
end

RSpec.describe EO::Locksmith do
  include_context 'a script lending helpers'

  let(:obj) { Struct.new(:id, :noun, :contents, :type, keyword_init: true) }
  let(:room_desc) { [] }
  let(:loot) { [] }
  let(:hands) { { right: obj.new, left: obj.new } }

  before do
    desc = room_desc
    floor = loot
    held = hands
    stub_const('GameObj', Class.new do
      define_singleton_method(:room_desc) { desc }
      define_singleton_method(:loot) { floor }
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
    end)
  end

  describe '.town_activator' do
    def table_with(*nouns) = room_desc << obj.new(id: '2', noun: 'table', contents: nouns.map { |n| obj.new(noun: n) })

    it 'rings a bell first, pulls keys next, and rings a chime last' do
      table_with('chime', 'keys', 'bell')
      expect(described_class.town_activator).to eq('ring bell')
      room_desc.first.contents.pop
      expect(described_class.town_activator).to eq('pull keys')
      room_desc.first.contents.pop
      expect(described_class.town_activator).to eq('ring chime')
    end

    it 'takes a chime lying in the room' do
      table_with('ledger')
      loot << obj.new(noun: 'chime')
      expect(described_class.town_activator).to eq('ring chime')
    end

    it 'looks on a table whose contents are not known, and says what was missing' do
      expect(described_class.town_activator).to eq(:no_table)
      loot << obj.new(id: '2', noun: 'counter', contents: nil)
      expect(described_class.town_activator).to eq(:no_contents)
      expect(sent).to eq(['look on #2'])
      loot.first.contents = []
      expect(described_class.town_activator).to eq(:nothing)
    end
  end

  describe 'a box at the town locksmith' do
    let(:box) { obj.new(id: '5') }
    let(:replies) { [] }

    before do
      queue = replies
      log = sent
      described_class.define_singleton_method(:dothistimeout) { |cmd, *_| log << cmd && queue.shift }
    end

    after { described_class.singleton_class.remove_method(:dothistimeout) }

    it 'is shut when LOOK IN says closed or shows it phased' do
      answers['look in #5'] = [['That is closed.'], ['You see the shifting form of a chest.'], ['<container id="5"/>']]
      expect([described_class.shut?(box), described_class.shut?(box), described_class.shut?(box)]).to eq([true, true, false])
    end

    it 'is locked when OPEN says so' do
      answers['open #5'] = [['It appears to be locked.'], ['You open the chest.']]
      expect([described_class.locked?(box), described_class.locked?(box)]).to eq([true, false])
    end

    it 'calls the locksmith, reads the fee, and pays' do
      replies.push('"Gimme 1,200 silvers," he says.', 'He accepts your silvers.')
      answer = described_class.call('ring bell')
      expect(described_class.fee(answer)).to eq(1200)
      expect(described_class.pay).to match(/accepts/)
      expect(sent).to eq(['ring bell', 'pay'])
      expect(described_class.fee('The locksmith ignores you.')).to be_nil
    end
  end

  describe EO::Locksmith::Pool do
    let(:worker) { obj.new(id: '30') }

    it 'puts a box already in hand first, and each box once' do
      held = obj.new(id: '1', type: 'box')
      other = obj.new(id: '2', type: 'box')
      order = described_class.order(held: [obj.new(id: '9', type: 'weapon'), held], found: [other, held], passed: [other, obj.new(id: '3', type: 'box')])
      expect(order.map(&:id)).to eq(%w[1 2 3])
    end

    it 'gives with the tip, and confirms on the second give' do
      log = []
      described_class.define_singleton_method(:dothistimeout) { |cmd, *_| log << cmd }
      described_class.give(worker, '5 PERCENT')
      described_class.give(worker, 250, confirm: true)
      described_class.ask_return(worker)
      expect(log).to eq(['give #30 5 PERCENT', 'give #30 250 confirm', 'ask #30 for return'])
    ensure
      described_class.singleton_class.remove_method(:dothistimeout)
    end

    it 'finds the box handed back, the right hand before the left' do
      allow(described_class).to receive(:sleep)
      expect(described_class.returned_box).to be_nil
      expect(described_class).to have_received(:sleep).exactly(20).times
      hands[:left] = obj.new(id: '7', type: 'plinite')
      expect(described_class.returned_box.id).to eq('7')
      hands[:right] = obj.new(id: '8', type: 'box')
      expect(described_class.returned_box.id).to eq('8')
    end

    describe '.depth' do
      let(:list) do
        ["Sure, here's the list of boxes we have for you.", '1. A steel chest.  It is ready to be RETURNED.', '2. An iron coffer.',
         '3. A wooden box.']
      end

      it 'counts the boxes not ready to come back' do
        answers['ask #30 about list'] = list + ['<prompt time="1">&gt;</prompt>']
        expect(described_class.depth(worker)).to eq([2, true])
      end

      it 'counts a list cut short again from the buffer, and says it was not whole' do
        answers['ask #30 about list'] = list.first(3)
        buffer = ['an older line'] + list
        described_class.define_singleton_method(:reget) { buffer }
        expect(described_class.depth(worker)).to eq([2, false])
      ensure
        described_class.singleton_class.remove_method(:reget)
      end

      it 'counts nothing for a customer with no boxes there' do
        expect(described_class.counts(["You haven't given us any boxes to be worked on."])).to eq([0, 0])
        expect(described_class.counts(['nothing of the kind'])).to eq([0, 0])
      end
    end

    it 'tips more as the pool fills, between the base and the most' do
      expect(described_class.tip(1, 100, 1000, 2)).to eq(100)
      expect(described_class.tip(50, 100, 1000, 2)).to eq(325)
      expect(described_class.tip(100, 100, 1000, 2)).to eq(1000)
    end

    it 'sums the tip over the places the boxes will take, up to the hundredth' do
      expect(described_class.tip_for(49, 1, base: 100, max: 1000, alpha: 2)).to eq(325)
      expect(described_class.tip_for(98, 5, base: 100, max: 1000, alpha: 2)).to eq(described_class.tip(99, 100, 1000, 2) + 1000)
    end
  end
end
