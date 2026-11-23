# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/casting'

RSpec.describe EO::Casting do
  let(:spell) { Struct.new(:circle, :results) }

  def skills(emc: 0, smc: 0, mmc: 0)
    stub_const('Skills', Class.new do
      define_singleton_method(:emc) { emc }
      define_singleton_method(:smc) { smc }
      define_singleton_method(:mmc) { mmc }
    end)
  end

  def prof(name) = stub_const('Stats', Class.new { define_singleton_method(:prof) { name } })

  it 'allows one more cast per 25 lore ranks in the circles the spell draws on' do
    prof('Wizard')
    skills(emc: 74)
    expect(described_class.max_multicast(spell.new(4))).to eq(3)
    prof('Empath')
    skills(smc: 50, mmc: 50)
    expect(described_class.max_multicast(spell.new(11))).to eq(4)
    expect(described_class.max_multicast(spell.new(1))).to eq(4)
    expect(described_class.max_multicast(spell.new(7))).to eq(1)
    prof('Warrior')
    skills(emc: 30, smc: 10)
    expect(described_class.max_multicast(spell.new(4))).to eq(2)
  end

  it 'casts at a target or at oneself and reads the answer' do
    caster = Class.new do
      attr_reader :sent

      def initialize(answers) = (@answers = answers) && (@sent = [])

      def cast(arg = nil)
        @sent << arg
        @answers.shift
      end
    end
    spell = caster.new(['[Spell Hindrance for Mage Armor]', 'You cast'])
    expect(described_class.cast(spell, target: 'Ann', multicast: 3)).to eq(:success)
    expect(spell.sent).to eq(['at Ann 3', 'at Ann 3'])
    expect(described_class.cast(caster.new(['Cast at what?']), target: 'Bob')).to eq(:bad_target)
    expect(described_class.cast(caster.new(['Spells of War cannot be cast here.']))).to eq(:refused_here)
    self_cast = caster.new(['You cast'])
    described_class.cast(self_cast, argument: 'shield')
    expect(self_cast.sent).to eq(['shield'])

    stuck = caster.new(['[Spell Hindrance for Mage Armor]'] * 5)
    expect(described_class.cast(stuck)).to eq(:hindered)
    expect(stuck.sent.size).to eq(described_class::MAX_HINDERED)
  end

  context 'when short of mana with someone watching who is not of the Council' do
    let(:sign) do
      Class.new do
        attr_reader :casts

        def initialize = @casts = 0
        def affordable? = true
        def active? = false
        def cast = @casts += 1
      end.new
    end
    let(:wanted) do
      Class.new do
        attr_accessor :affordable

        def mana_cost(**) = 10
        def affordable?(**) = affordable
      end.new
    end
    let(:walked) { [] }

    before do
      the_sign = sign
      steps = walked
      stub_const('Spell', Class.new { define_singleton_method(:[]) { |_num| the_sign } })
      stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:id, :tags).new(steps.size, []) } })
      %i[invisible? hidden?].each { |m| described_class.define_singleton_method(m) { false } }
      %i[waitrt? waitcastrt?].each { |m| described_class.define_singleton_method(m) { nil } }
      described_class.define_singleton_method(:checkpcs) { ['Someone'] }
      allow(described_class).to receive(:safe_to_wrack?).and_return(false)
      allow(EO).to receive(:wander) { |visited| steps << visited }
      allow(EO).to receive(:go2) { |place| steps << [:back, place] }
    end

    after { %i[invisible? hidden? waitrt? waitcastrt? checkpcs].each { |m| described_class.singleton_class.remove_method(m) } }

    it 'does not wrack where it stands, and bails' do
      expect(described_class.ready(wanted, 1, described_class::Resources.new(source: :wracking, bail: true))).to eq(:bail)
      expect(sign.casts).to eq(0)
      expect(walked).to be_empty
    end

    it 'does not wrack after walking twenty rooms and finding nowhere, and comes back' do
      resources = described_class::Resources.new(source: :wracking, bail: true, wander_to_wrack: true)
      expect(described_class.ready(wanted, 1, resources)).to eq(:bail)
      expect(sign.casts).to eq(0)
      expect(walked.size).to eq(21)
      expect(walked.last).to eq([:back, 0])
    end

    it 'wracks in the room the walk found, and comes back' do
      allow(described_class).to receive(:safe_to_wrack?) { walked.size >= 3 }
      stub_const('Char', Class.new { define_singleton_method(:mana) { 100 } })
      allow(sign).to receive(:cast).and_wrap_original do |original|
        wanted.affordable = true
        original.call
      end
      resources = described_class::Resources.new(source: :wracking, wander_to_wrack: true)
      expect(described_class.ready(wanted, 1, resources)).to eq(:ready)
      expect(sign.casts).to eq(1)
      expect(walked.last).to eq([:back, 0])
    end
  end

  it 'gives the resources sensible defaults' do
    r = described_class::Resources.new(reserve: '20')
    expect([r.reserve, r.source, r.bail, r.wander_to_wrack]).to eq([20, nil, false, false])
  end
end
