# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/brooch'
require_relative '../../scripts/eo/chain'

RSpec.describe EO::Chain do
  let(:fxp) { [1800, 1800] }

  before do
    spec = self
    stub_const('Experience', Module.new do
      define_singleton_method(:fxp_current) { spec.fxp[0] }
      define_singleton_method(:fxp_max) { spec.fxp[1] }
    end)
  end

  describe '.reduce' do
    it 'does nothing at or under the cap' do
      expect(EO).not_to receive(:result)
      expect(described_class.reduce(%w[longterm spirit])).to be_nil
    end

    it 'uses one reducer, the first that works' do
      fxp[0] = 2400
      allow(EO).to receive(:result).and_return('You do not have any Long-Term Experience Boosts to redeem.')
      allow(EO::Brooch).to receive(:use).with(:spirit).and_return(:spirit)
      expect(described_class.reduce(%w[longterm spirit])).to eq(:spirit)
    end

    it 'skips the reducer when the overflow absorbs before the next turn-in can come' do
      fxp[0] = 2100 # 300 over
      allow(described_class).to receive(:absorb_per_minute).and_return(30.0) # ten minutes to absorb
      expect(EO).not_to receive(:result)
      expect(described_class.reduce(%w[longterm], window: 12)).to eq(:absorbs)
    end

    it 'reduces when it will not absorb in time' do
      fxp[0] = 2100
      allow(described_class).to receive(:absorb_per_minute).and_return(30.0)
      allow(EO).to receive(:result).and_return('You have deducted 500 experience points from your field experience.')
      expect(described_class.reduce(%w[longterm], window: 5)).to eq(:longterm)
    end

    it 'stops after a long-term boost' do
      fxp[0] = 2400
      allow(EO).to receive(:result).and_return('You have deducted 500 experience points from your field experience and added 250 to your long-term experience.')
      expect(EO::Brooch).not_to receive(:use)
      expect(described_class.reduce(%w[longterm spirit])).to eq(:longterm)
    end
  end

  describe '.before_turn_in' do
    it 'rubs planar and order only when their effect is not up' do
      allow(EO::Brooch).to receive(:up?).with(:planar).and_return(true)
      allow(EO::Brooch).to receive(:up?).with(:order).and_return(false)
      expect(EO::Brooch).to receive(:use).with(:order).and_return(:order)
      expect(described_class.before_turn_in(planar: true, order: true)).to eq(order: :order)
    end
  end
end
