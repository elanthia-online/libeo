# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/herbs/table'
require_relative '../../scripts/eo/herbs/doses'
require_relative '../../scripts/eo/herbs/sack'

# A Survivalist's Kit: how ANALYZE and LOOK IN describe it, and what its
# extractor is pointed at. The lines are the game's own, from the 2026-01-31
# log (kit 506565738), with the herb lists cut down to a few herbs.
RSpec.describe EO::Herbs::Sack, 'as a Survivalist\'s Kit' do
  let(:kit_object) { Struct.new(:id, :name, :noun, :contents).new('506565738', 'leather herb kit', 'kit', []) }
  let(:kit) { described_class.new(kit_object) }
  let(:link) { '<a exist="506565738" noun="kit">kit</a>' }

  # ANALYZE
  let(:analyze_head) do
    ['You analyze the <a exist="506565738" noun="kit">leather herb kit</a> and sense that the creator has provided the following information:',
     "The <a exist=\"506565738\" noun=\"kit\">leather herb kit</a> is a Survivalist's Kit, which is a specialized container for storing healing herbs.  " \
     'All herbs stack up to 50 by default and maintain the weight of a single dose.',
     'This <a exist="506565738" noun="kit">kit</a> has the Liquid Storage unlock, which allows it to store liquid herbs in addition to their solid counterparts.']
  end
  let(:extractor_line) do
    'This <a exist="506565738" noun="kit">kit</a> has the Liquid Extractor unlock, which allows it to convert solid herbs into liquid over time ' \
      '(1 per 20 minutes).  The solid herb target must first be set by POINTing the <a exist="506565738" noun="kit">kit</a> at the appropriate dose ' \
      'of the herb inside of it, which should automatically begin the process.  You may then NUDGE the kit to stop (or restart) the extractor.  '
  end
  let(:targeting) { 'The extractor is currently targeting <pushBold/>basal<popBold/>, with around nine minutes remaining.' }
  let(:capacity) { 'Capacity: 5/5 (150 charges maximum per herb)' }

  # the kit's herb lists, from "Current herb stock:" and from LOOK IN
  def solids(*herbs) = "The #{link} contains DOSEs of the following solid herbs: #{listing(herbs)}."
  def liquids(*herbs) = "The #{link} contains TINCTUREs of the following liquid herbs: #{listing(herbs)}."

  def listing(herbs)
    herbs.map { |exist, noun, count| "<a exist=\"#{exist}\" noun=\"#{noun}\">#{noun}</a> (#{count})" }.join(', ')
  end

  describe '#analyze!' do
    def analyze_with(lines)
      allow(EO).to receive(:command).and_return(lines)
      kit.analyze!
    end

    it 'knows the kit, its capacity tier and its extractor' do
      expect(analyze_with(analyze_head + [extractor_line + targeting, capacity])).to be(true)
      expect(kit.tier).to eq(5)
      expect(kit.distiller).to be(true)
    end

    it 'is a kit without an extractor when the unlock is not there' do
      expect(analyze_with(analyze_head + [capacity])).to be(true)
      expect(kit.distiller).to be(false)
    end
  end

  describe '#kit_contents' do
    let(:inv_line) { "<inv id='506565738'>In the <a exist=\"506565738\" noun=\"kit\">kit</a>:</inv>" }
    let(:look) do
      [inv_line, 'Total items: 5',
       "  #{solids(%w[506565760 acantha 62], %w[506565752 wolifrew 144], %w[506565756 basal 76])}  " \
       "#{liquids(%w[506565770 acantha 148], %w[506565749 wolifrew 150])}"]
    end

    before do
      $eherbs_measure = {}
      allow(EO).to receive(:command).and_return(look)
      stub_const('GameObj', Class.new do
        define_singleton_method(:new_inv) { |exist, noun, name, _| Struct.new(:id, :noun, :name).new(exist, noun, name) }
        define_singleton_method(:[]) { |_id| Struct.new(:contents).new([]) }
      end)
    end

    after { $eherbs_measure = {} }

    it 'lists the solid herbs as edible and the liquid ones as drinkable, with their doses' do
      items = kit.kit_contents
      expect(items[:edible].map(&:name)).to eq(%w[acantha wolifrew basal])
      expect(items[:drinkable].map(&:name)).to eq(%w[acantha wolifrew])
      expect(items[:all].size).to eq(5)
    end

    it 'keeps the doses the kit reports, by the herb\'s id' do
      kit.kit_contents
      expect(EO::Herbs::Doses['506565760']).to eq(62)
      expect(EO::Herbs::Doses['506565756']).to eq(76)
      expect(EO::Herbs::Doses['506565770']).to eq(148)
    end

    it 'asks LOOK IN for this kit only' do
      kit.kit_contents
      expect(EO).to have_received(:command).with('look in #506565738', anything, silent: true, quiet: true)
    end

    it 'lists nothing for an empty kit' do
      allow(EO).to receive(:command).and_return([inv_line, 'There is nothing in the kit.'])
      expect(kit.kit_contents).to eq(drinkable: [], edible: [], all: [])
    end
  end

  describe '#distill' do
    # lines: what ANALYZE gives back
    def distill_with(lines, distiller: true, survival_kit: true)
      kit.distiller = distiller
      kit.survival_kit = survival_kit
      allow(EO).to receive(:command).and_return(lines)
      messages = []
      stub_const('Lich::Messaging', Module.new.tap { |m| m.define_singleton_method(:msg) { |_kind, text| messages << text } })
      allow(kit).to receive(:fput)
      [kit.distill, messages]
    end

    let(:stock) do
      "Current herb stock: #{solids(%w[1 acantha 62], %w[2 wolifrew 144], %w[3 basal 76])}  " \
        "#{liquids(%w[4 acantha 148], %w[5 wolifrew 150])}"
    end

    it 'does nothing for a kit with no extractor, or a sack that is no kit' do
      expect(distill_with([stock], distiller: false).first).to be_nil
      expect(distill_with([stock], survival_kit: false).first).to be_nil
      expect(kit).not_to have_received(:fput)
    end

    it 'does nothing when the game says it cannot' do
      expect(distill_with(["You can't seem to do that.", stock]).first).to be_nil
      expect(kit).not_to have_received(:fput)
    end

    it 'leaves an extractor alone that is already working, and says what at' do
      target, messages = distill_with([extractor_line + targeting, stock])
      expect(target).to be_nil
      expect(messages.join).to include('currently targeting basal')
      expect(kit).not_to have_received(:fput)
    end

    it 'points it at a solid herb that has no liquid yet' do
      target, = distill_with([extractor_line, stock])
      expect(target).to eq('basal')
      expect(kit).to have_received(:fput).with('point #506565738 at dose basal')
    end

    it 'points it at the first of several solid herbs that have no liquid' do
      several = "Current herb stock: #{solids(%w[1 acantha 62], %w[2 wolifrew 144], %w[3 basal 76], %w[6 ephlox 20])}  #{liquids(%w[4 acantha 148])}"
      expect(distill_with([several]).first).to eq('wolifrew')
    end

    it 'points it at the lowest liquid when every solid has some' do
      all_have = "Current herb stock: #{solids(%w[1 acantha 62], %w[2 wolifrew 144])}  #{liquids(%w[4 acantha 148], %w[5 wolifrew 150])}"
      target, = distill_with([all_have])
      expect(target).to eq('acantha')
      expect(kit).to have_received(:fput).with('point #506565738 at dose acantha')
    end

    it 'has nothing to point at without solid herbs' do
      expect(distill_with(["Current herb stock: #{liquids(%w[4 acantha 148])}"]).first).to be_nil
      expect(kit).not_to have_received(:fput)
    end
  end
end
