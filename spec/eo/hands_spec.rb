# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/hands'

RSpec.describe EO::Hands do
  describe '.store' do
    let(:disk) { Struct.new(:id, :name, :contents).new('9', 'Nisugi disk', []) }
    let(:coffer) { Struct.new(:id, :name).new('5', 'scratched haon coffer') }
    let(:sent) { [] }

    # answer: the _drag's lines; before/after: in hand before and after it
    def store_with(answer:, before:, after:)
      held = [before]
      allow(described_class).to receive(:holding?) { held.size > 1 ? after : held.shift.tap { held << after } }
      allow(EO).to receive(:command) { |cmd, *| sent << cmd; answer }
      allow(described_class).to receive(:sleep)
      described_class.store(disk, coffer)
    end

    it 'is :stored once an item on the floor has left it, whatever the wording, with no look in the disk' do
      room = [coffer]
      stub_const('GameObj', Module.new { define_singleton_method(:loot) { room } })
      allow(EO).to receive(:command) { |cmd, *| sent << cmd; room.clear; ['Your disk takes the coffer.'] }
      allow(described_class).to receive(:holding?).and_return(false)
      expect(described_class.store(disk, coffer)).to eq(:stored)
      expect(sent).to eq(['_drag #5 #9'])
    end

    it 'does not take a put of a floor item for stored while it still lies there' do
      room = [coffer]
      stub_const('GameObj', Module.new { define_singleton_method(:loot) { room } })
      allow(EO).to receive(:command) { |cmd, *| sent << cmd; ['You put a scratched haon coffer in the disk.'] }
      allow(described_class).to receive(:holding?).and_return(false)
      allow(described_class).to receive(:sleep)
      allow(described_class).to receive(:waitrt?)
      stub_const('EO::Containers', Module.new { const_set(:LOOK, /look/) })
      expect(described_class.store(disk, coffer)).not_to eq(:stored)
    end

    it 'is :stored once an item in hand has left it, whatever the wording' do
      expect(store_with(answer: ['You drop the coffer into the disk.'], before: true, after: false)).to eq(:stored)
      expect(sent).to eq(['_drag #5 #9'])
    end

    it 'is :full on the refusal, the item still in hand' do
      expect(store_with(answer: ["It won't fit in the disk."], before: true, after: true)).to eq(:full)
    end
  end

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
