# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/guild/forage'

RSpec.describe EO::Guild::Forage do
  describe 'names' do
    it 'turns the task wording for ayana into what FORAGE wants' do
      expect(described_class.forage_name('ayana berry')).to eq('ayana leaf')
      expect(described_class.forage_name("ayana'al root")).to eq("ayana'al leaf")
      expect(described_class.forage_name('acantha leaf')).to eq('acantha leaf')
      expect(described_class.forage_name('Ayana Berry')).to eq('ayana leaf')
    end

    it 'expands the mushroom names the task shortens' do
      expect(described_class.stow_name('white mushroom')).to eq('white hook mushroom')
      expect(described_class.stow_name('trafel mushroom')).to eq('black trafel mushroom')
      expect(described_class.stow_name('acantha leaf')).to eq('acantha leaf')
      expect(described_class.stow_name('golden mushroom')).to eq('golden hook mushroom')
    end

    it 'matches a container item to the herb, including an ayana part' do
      expect(described_class.match?('some white hook mushroom', 'white mushroom')).to be(true)
      expect(described_class.match?('ayana', 'ayana leaf')).to be(true)
      expect(described_class.match?('acantha', 'acantha leaf')).to be(false)
      expect(described_class.match?('some acantha leaf', 'acantha leaf')).to be(true)
    end

    it 'matches without regard to case' do
      expect(described_class.match?("sprig of Imaera's Lace", "sprig of imaera's lace")).to be(true)
      expect(described_class.match?('some acantha leaf', 'Acantha Leaf')).to be(true)
      expect(described_class.match?('Ayana', 'ayana leaf')).to be(true)
      expect(described_class.match?('golden hook mushroom', 'golden mushroom')).to be(true)
    end
  end

  describe '.rooms' do
    include_context 'a fake map'

    let(:rooms) do
      chain = (1..12).map do |id|
        exits = {}
        exits[(id - 1).to_s] = 'w' if id > 1
        exits[(id + 1).to_s] = 'e' if id < 12
        tags = id.even? ? ['herb:acantha leaf'] : []
        tags << 'herb:wolifrew lichen' if id == 3
        tags << "sprig of Imaera's Lace" if id == 5
        EOSpec::FakeRoom.new(id: id, location: id > 6 ? 'Far Field' : 'Near Field', tags: tags, wayto: exits)
      end
      chain
    end

    before { map.current = map[1] }

    it 'lists rooms tagged with the herb, nearest first, at most ten' do
      ids = described_class.rooms('acantha leaf', 'acantha leaf')
      expect(ids).to eq([2, 4, 6, 8, 10, 12])
    end

    it 'keeps only the named location when one is given' do
      expect(described_class.rooms('acantha leaf', 'acantha leaf', 'Far Field')).to eq([8, 10, 12])
    end

    it 'finds a tag written in another case than the herb' do
      expect(described_class.rooms("sprig of imaera's lace", "sprig of imaera's lace")).to eq([5])
    end

    it 'takes a location in another case when the exact one finds no room' do
      expect(described_class.rooms('acantha leaf', 'acantha leaf', 'far field')).to eq([8, 10, 12])
    end

    it 'keeps to the exact case of a location when that finds rooms' do
      map[2].location = 'near field'
      expect(described_class.rooms('acantha leaf', 'acantha leaf', 'Near Field')).to eq([4, 6])
    end

    it 'finds nothing for an herb no room carries' do
      expect(described_class.rooms('rose-marrow potion', 'rose-marrow potion')).to eq([])
    end
  end

  describe '.slots_left' do
    def sense(ranks, last_line)
      stub_const('Skills', Module.new { define_singleton_method(:survival) { ranks } })
      allow(EO).to receive(:command).and_return(['Glancing about, you notice the immediate area should support specimens of small flower.', last_line])
      described_class.slots_left
    end

    it 'reads the slots from the last line of FORAGE SENSE' do
      expect(sense(25, 'The surroundings look lush and verdant.')).to eq(5)
      expect(sense(25, 'The surroundings look a bit browsed.')).to eq(3)
      expect(sense(25, 'The surroundings look picked over.')).to eq(2)
      expect(sense(25, 'The surroundings look scavenged.')).to eq(1)
      expect(sense(25, 'As you glance around, it becomes apparent that someone has been foraging around here recently and you will be unable to find anything useful.')).to eq(0)
    end

    it 'does not try without the Survival for it' do
      expect(EO).not_to receive(:command)
      expect(sense(24, '')).to be_nil
    end
  end

  describe '.forage_once' do
    def forage(line)
      allow(EO).to receive(:result).and_return(line)
      allow(EO).to receive(:settle)
      allow(described_class).to receive(:stow_found)
      described_class.forage_once('acantha leaf', :sack)
    end

    it 'tells a find, an empty room, and an herb that does not grow here apart' do
      expect(forage('You forage briefly and manage to find some acantha leaf!')).to eq(:found)
      expect(forage('As you forage around, you notice that someone has been foraging here recently and you are unable to find anything useful.')).to eq(:picked_over)
      expect(forage('As you carefully forage around you can find no hint of what you are looking for.')).to eq(:not_here)
      expect(forage('You stumble about in a fruitless attempt at foraging.')).to eq(:missed)
    end

    # the game's lines, the first from the January logs (132 of them)
    [
      'As you carefully forage around you find no trace of what you are looking for.  You are not even sure it could be found in this type of climate.',
      'As you carefully forage around you can find no hint of what you are looking for right now, though you are fairly certain this is where it can be found.',
      'As you carefully forage around you can find no trace of what you are looking for.  You briefly wonder if it could even thrive in this place.',
      'As you carefully forage around you see no evidence of what you are looking for.'
    ].each do |line|
      it "moves on from: #{line[36, 60]}" do
        expect(line).to match(EO::Guild::Tables::FORAGE_RESULT)
        expect(forage(line)).to eq(:not_here)
      end
    end
  end
end
