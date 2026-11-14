# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/herbs/table'
require_relative '../../scripts/eo/herbs/doses'
require_relative '../../scripts/eo/herbs/sack'
require_relative '../../scripts/eo/herbs/shop'

# The herbalist's arithmetic: what a shopping list needs and costs, how it is
# bought, and how a purchase is counted. Only the game's own calls are stood in
# for; the herb table is the real one (Ta'Vaalor sells acantha, 10 doses a
# unit, for blood).
RSpec.describe EO::Herbs::Shop do
  let(:town) { "Ta'Vaalor" }
  let(:thing) { Struct.new(:id, :name) }
  let(:acantha) { thing.new('5', 'tincture of acantha') }

  before { $eherbs_measure = {} }
  after { $eherbs_measure = {} }

  describe '.cost' do
    it 'adds up each line at its price and a tenth over, dropping the fraction' do
      prices = { 'blood' => { cost: 100 }, 'major limb wound' => { cost: 50 } }
      list = [{ category: 'blood', needed: 3 }, { category: 'major limb wound', needed: 1 }]
      expect(described_class.cost(list, prices)).to eq(385)
      expect(described_class.cost([{ category: 'blood', needed: 15 }], { 'blood' => { cost: 1 } })).to eq(16)
    end

    it 'prices both tiers of blood as blood' do
      list = [{ category: 'minor blood', needed: 2 }, { category: 'major blood', needed: 3 }]
      expect(described_class.cost(list, { 'blood' => { cost: 10 } })).to eq(55)
    end

    it 'names the category that has no price' do
      expect { described_class.cost([{ category: 'severed limb', needed: 1 }], {}) }
        .to raise_error(EO::Guild::Error, /no price for severed limb/)
    end
  end

  describe '.shopping_list' do
    # held: doses already in the sack of the acantha in it
    def list_for(held:, target: 50, items: [acantha], category: 'blood', location: town)
      $eherbs_measure['5'] = held if held
      sack = double('sack', survival_kit: false, obj: double(contents: []), contents: { all: items })
      described_class.shopping_list(sack, [category], targets: { category => target }, location: location)
    end

    it 'needs whole units for what is missing: doses short divided by the doses a unit holds' do
      line = list_for(held: 4).first
      expect(line).to include(category: 'blood', herb_name: 'tincture of acantha', needed: 4) # (50 - 4) / 10
      expect(line[:herb_list]).to eq([acantha])
    end

    it 'buys nothing when the sack holds the target, or less than a unit is short' do
      expect(list_for(held: 50)).to be_empty
      expect(list_for(held: 45)).to be_empty
    end

    it 'buys the first of a kind the sack holds none of' do
      line = list_for(held: nil, items: []).first
      expect(line).to include(category: 'blood', needed: 5, herb_list: [])
    end

    it 'buys nothing for a target of nothing, even when the sack holds none' do
      expect(list_for(held: nil, items: [], target: 0)).to be_empty
    end

    it 'skips a category the town does not sell' do
      expect(list_for(held: nil, items: [], location: 'Nowhere')).to be_empty
    end
  end

  describe '.buy_list' do
    let(:bought) { [] }
    let(:sack) { double('sack', survival_kit: false, store: nil, take: nil) }

    before do
      allow(described_class).to receive(:empty_hands)
      allow(described_class).to receive(:bundle_all)
      allow(described_class).to receive(:put_away).and_return(acantha)
      allow(EO::Herbs::Sack).to receive(:herb_in_hand).and_return(nil)
      allow(described_class).to receive(:buy) { |category, amount, **| bought << [category, amount] }
    end

    def buy(needed, note: nil)
      described_class.buy_list([{ category: 'blood', needed: needed }], sack: sack, menu: {}, location: town, note: note)
    end

    it 'buys ten at a time and the rest last' do
      buy(23)
      expect(bought).to eq([['blood', 10], ['blood', 10], ['blood', 3]])
      bought.clear
      buy(27)
      expect(bought).to eq([['blood', 10], ['blood', 10], ['blood', 7]])
    end

    it 'buys a lot of ten and no remainder, or a remainder alone' do
      buy(10)
      expect(bought).to eq([['blood', 10]])
      bought.clear
      buy(4)
      expect(bought).to eq([['blood', 4]])
      bought.clear
      buy(15)
      expect(bought).to eq([['blood', 10], ['blood', 5]])
    end

    it 'bundles what it bought only when it bought more than one' do
      buy(1)
      expect(described_class).to have_received(:bundle_all).twice # before, and after
      buy(2)
      expect(described_class).to have_received(:bundle_all).with(sack, 'tincture of acantha')
    end

    it 'carries the note in hand while it buys and puts it away after' do
      note = thing.new('9', 'bank note')
      buy(1, note: note)
      expect(sack).to have_received(:take).with(note).at_least(:once)
      expect(sack).to have_received(:store).with(note).at_least(:once)
    end

    it 'refuses a category the town does not sell' do
      expect do
        described_class.buy_list([{ category: 'blood', needed: 1 }], sack: sack, menu: {}, location: 'Nowhere')
      end.to raise_error(EO::Guild::Error, /no herb sold here for blood/)
    end
  end

  describe '.buy' do
    let(:menu) { { 'tincture of acantha' => '7' } }
    let(:sack) { double('sack', id: '1') }
    let(:sent) { [] }

    # answers: what the game says to each command, in turn after the order
    def buy_with(*answers, more_silver: nil, category: 'blood', menu: self.menu)
      queue = answers.dup
      allow(described_class).to receive(:dothistimeout) do |cmd, *|
        sent << cmd
        cmd.start_with?('order') ? 'BUY' : queue.shift
      end
      allow(described_class).to receive_messages(checkright: false, checkleft: false)
      allow(EO::Herbs::Sack).to receive(:herb_in_hand).and_return(acantha)
      described_class.buy(category, 10, menu: menu, sack: sack, more_silver: more_silver)
    end

    it 'orders the amount by the menu number and counts the doses of what it bought' do
      buy_with('Sold for 1,200 silver.')
      expect(sent).to eq(['order 10 7', 'buy'])
      expect(EO::Herbs::Doses['5']).to eq(10)
    end

    it 'says so when there is no silver and no way to get more' do
      expect { buy_with('But you do not have enough silver!') }.to raise_error(EO::Guild::Error, /not enough silver/)
    end

    it 'fetches silver once and then buys again without asking for more' do
      fetched = 0
      buy_with('But you do not have enough silver!', 'Sold for 1,200 silver.', more_silver: -> { fetched += 1 })
      expect(fetched).to eq(1)
      expect(sent.count('buy')).to eq(2)
      expect(EO::Herbs::Doses['5']).to eq(10)
    end

    it 'does not fetch silver twice when the second try fails too' do
      fetched = 0
      expect { buy_with('But you do not have enough silver!', 'But you do not have enough silver!', more_silver: -> { fetched += 1 }) }
        .to raise_error(EO::Guild::Error, /not enough silver/)
      expect(fetched).to eq(1)
    end

    it 'names the category when the menu has nothing for it' do
      expect { buy_with('Sold for 1 silver.', menu: {}) }.to raise_error(EO::Guild::Error, /failed to find blood/)
    end
  end
end
