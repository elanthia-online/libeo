# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/hands'

RSpec.describe EO::Hands do
  describe '.wear' do
    let(:sack) { Struct.new(:id, :name).new('55', 'leather sack') }

    # held: still in hand after the command; answer: the game's reply
    def wear_with(answer:, held:, worn: false)
      allow(EO).to receive(:result).and_return(answer)
      allow(described_class).to receive(:holding?).and_return(held)
      allow(described_class).to receive(:sleep)
      stub_const('GameObj', Class.new { define_singleton_method(:inv) { worn ? [Struct.new(:id).new('55')] : [] } })
      described_class.wear(sack)
    end

    it 'is :worn once the item has left the hand for the inventory' do
      expect(wear_with(answer: 'You attach a leather sack.', held: false, worn: true)).to eq(:worn)
    end

    it 'is :cant when the game says it cannot be worn and it is still in hand' do
      expect(wear_with(answer: "You can't wear that.", held: true)).to eq(:cant)
    end

    it 'is :stuck when it stays in hand with no refusal' do
      expect(wear_with(answer: nil, held: true)).to eq(:stuck)
    end

    it 'is :cant for no item or an empty hand' do
      expect(described_class.wear(nil)).to eq(:cant)
      expect(described_class.wear(Struct.new(:id, :name).new(nil, 'Empty'))).to eq(:cant)
    end
  end
end
