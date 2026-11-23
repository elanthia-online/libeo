# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/herbs/heal'
require_relative '../../scripts/eo/herbs/shop'

RSpec.describe 'pouring potions' do
  let(:potion) { Struct.new(:id, :name, :noun).new('9', 'tincture of ephlox', 'tincture') }

  describe EO::Herbs::Heal, '.deader' do
    let(:dead) { Struct.new(:status) { def to_s = 'Dicate' }.new('dead') }
    let(:appraisals) { [] }

    # pour: what the game answers to a pour
    def deader_with(pour:)
      appraised = appraisals
      table = Module.new
      table.define_singleton_method(:cures?) { |*| true }
      table.define_singleton_method(:drinkable?) { |*| true }
      injuries = Module.new
      injuries.define_singleton_method(:appraise) { |*, **| [:wound] } # the wounds never heal
      stub_const('EO::Herbs::Table', table)
      stub_const('EO::Herbs::Injuries', injuries)
      held = potion
      stub_const('GameObj', Class.new do
        define_singleton_method(:right_hand) { held }
        define_singleton_method(:left_hand) { Struct.new(:name, :noun, :id).new('Empty', nil, nil) }
      end)
      allow(EO).to receive(:command) do |*|
        appraised << 1
        ['You take a quick appraisal']
      end
      allow(described_class).to receive(:empty_right_hand)
      allow(described_class).to receive(:dothistimeout).and_return(pour)
      described_class.deader(dead, sack: nil)
    end

    it 'gives up at once when a pour is not answered' do
      expect(deader_with(pour: nil)).to eq(:timeout)
      expect(appraisals.size).to eq(1)
    end

    it 'gives up after its passes when the wounds never heal' do
      expect(deader_with(pour: 'You pour a tincture over him.')).to eq(:timeout)
      expect(appraisals.size).to eq(described_class::DEADER_PASSES)
    end
  end

  describe EO::Herbs::Shop, '.pour_into' do
    let(:bundle) { Struct.new(:id).new('4') }

    def pour_answering(*answers)
      queue = answers.dup
      sent = []
      allow(described_class).to receive(:dothistimeout) do |cmd, *|
        sent << cmd
        queue.empty? ? answers.last : queue.shift
      end
      [described_class.pour_into(potion, bundle), sent]
    end

    it 'stops when the bundle is full' do
      result, sent = pour_answering('You have a little room left.', 'You can not pour any more.')
      expect(result).to match(/You can/)
      expect(sent.size).to eq(2)
    end

    it 'stops after its tries when the game keeps saying there is room' do
      _, sent = pour_answering('You have room for more.')
      expect(sent.size).to eq(described_class::BUNDLE_POURS)
    end

    it 'stops at once when the game does not answer' do
      result, sent = pour_answering(nil)
      expect(result).to be_nil
      expect(sent.size).to eq(1)
    end
  end
end
