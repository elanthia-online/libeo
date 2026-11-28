# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/travel/travel'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/guild/disablers'
require_relative '../../scripts/eo/guild/rescue'

RSpec.describe EO::Guild::Disablers do
  let(:npc) { Struct.new(:id, :name, :status, keyword_init: true) }
  let(:fake_spell) { Struct.new(:known?, :affordable?, :mana_cost, :active?, keyword_init: true) }
  let(:spells) { {} }

  # A known, affordable spell at a mana cost; the table's entry is in play.
  def know(num, cost:, active: false)
    spells[num] = fake_spell.new(known?: true, affordable?: true, mana_cost: cost, active?: active)
  end

  before do
    table = spells
    unknown = fake_spell.new(known?: false, affordable?: false, mana_cost: 0, active?: false)
    stub_const('Spell', Class.new { define_singleton_method(:[]) { |n| table[n] || unknown } })
    stub_const('Skills', Class.new { def self.elair = 0 })
    stub_const('GameObj', Class.new { def self.npcs = []; def self.targets = [] })
    described_class.define_singleton_method(:mana) { 100 }
    allow(described_class).to receive(:justice?).and_return(false)
  end

  after { described_class.singleton_class.remove_method(:mana) }

  it 'picks the cheapest spell the character knows and can afford' do
    know(201, cost: 1)
    know(501, cost: 5)
    know(1207, cost: 7)
    policy = described_class::Policy.new
    expect(described_class.best(policy, targets: [npc.new(id: 1, name: 'a kobold', status: '')], wounds: false)).to eq(201)
  end

  it 'keeps the mana the policy reserves' do
    know(201, cost: 1)
    know(501, cost: 5)
    policy = described_class::Policy.new(min_mana: 97)
    expect(described_class.best(policy, targets: [npc.new(id: 1, name: 'a kobold', status: '')], wounds: false)).to eq(201)
    expect(described_class.any?(described_class::Policy.new(min_mana: 100))).to be(false)
  end

  it 'takes the forced spell when it is castable' do
    know(201, cost: 1)
    know(617, cost: 17)
    policy = described_class::Policy.new(forced: 617)
    expect(described_class.best(policy, targets: [npc.new(id: 1, name: 'a kobold', status: '')], wounds: false)).to eq(617)
    expect(described_class::Policy.new(forced: 0).forced).to be_nil
    expect(described_class::Policy.new(forced: false).forced).to be_nil
  end

  it 'takes the forced spell though no spell of the table is known' do
    know(1234, cost: 4)
    policy = described_class::Policy.new(forced: 1234)
    expect(described_class.best(policy, targets: [npc.new(id: 1, name: 'a kobold', status: '')], wounds: false)).to eq(1234)
  end

  context 'when JUSTICE STATUS is asked' do
    let(:hooks) { {} }

    before do
      added = hooks
      stub_const('Script', Class.new { def self.current = Struct.new(:name).new('echild') })
      stub_const('DownstreamHook', Class.new do
        define_singleton_method(:add) { |name, hook| added[name] = hook }
        define_singleton_method(:remove) { |name| added.delete(name) }
      end)
      allow(described_class).to receive(:justice?).and_call_original
      allow(described_class).to receive(:sleep)
    end

    it 'reads the answer and keeps it off the screen' do
      allow(described_class).to receive(:put) { expect(hooks.values.first.call('There is no justice to speak of here.')).to be_nil }
      expect(described_class.justice?).to be(false)
      expect(hooks).to be_empty
    end

    it 'waits five seconds for an answer, and none counts as justice' do
      allow(described_class).to receive(:put)
      expect(described_class.justice?).to be(true)
      expect(described_class).to have_received(:sleep).exactly(described_class::JUSTICE_WAIT * 100).times
      expect(hooks).to be_empty
    end
  end

  it 'drops a spell the target shrugs off' do
    know(501, cost: 5)
    know(1207, cost: 7)
    policy = described_class::Policy.new
    ghost = [npc.new(id: 1, name: 'a ghost', status: '')]
    expect(described_class.best(policy, targets: ghost, wounds: false)).to eq(1207)
  end

  it 'under justice uses only the town-safe spells' do
    allow(described_class).to receive(:justice?).and_return(true)
    know(135, cost: 1)
    know(201, cost: 2)
    policy = described_class::Policy.new
    expect(described_class.best(policy, targets: [npc.new(id: 1, name: 'a kobold', status: '')], wounds: false)).to eq(201)
  end

  it 'with several targets prefers a sanctuary over any cheaper multi-target spell' do
    know(135, cost: 1)
    know(201, cost: 1)
    know(213, cost: 13)
    policy = described_class::Policy.new
    two = [npc.new(id: 1, name: 'a kobold', status: ''), npc.new(id: 2, name: 'a kobold', status: '')]
    expect(described_class.best(policy, targets: two, wounds: false)).to eq(213)
  end

  it 'with several targets and no sanctuary takes the cheapest multi-target spell' do
    know(135, cost: 1)
    know(201, cost: 1)
    know(504, cost: 4)
    policy = described_class::Policy.new
    two = [npc.new(id: 1, name: 'a kobold', status: ''), npc.new(id: 2, name: 'a kobold', status: '')]
    expect(described_class.best(policy, targets: two, wounds: false)).to eq(135)
    stub_const('Skills', Class.new { def self.elair = 20 })
    know(135, cost: 10)
    expect(described_class.best(policy, targets: two, wounds: false)).to eq(504)
  end

  it 'returns nothing when no disabler is known' do
    expect(described_class.best(described_class::Policy.new, targets: [], wounds: false)).to be_nil
  end

  it 'leaves out creatures already disabled or known untargetable' do
    policy = described_class::Policy.new(untargetable: ['a statue'])
    stub_const('GameObj', Class.new do
      define_singleton_method(:targets) do
        [Struct.new(:name, :status).new('a kobold', ''), Struct.new(:name, :status).new('a kobold', 'stunned'),
         Struct.new(:name, :status).new('a statue', '')]
      end
    end)
    expect(described_class.live_targets(policy).map(&:name)).to eq(['a kobold'])
  end
end

RSpec.describe EO::Guild::Rescue do
  it 'knows every home a child names, by the town square' do
    expect(described_class::HOMES["Wehnimer's Landing"]).to eq('u7120')
    expect(described_class::HOMES['the County of Torre']).to eq(EO::Guild::Tables::TOWN_UIDS["River's Rest"])
    expect(described_class::HOMES['Vornavis']).to eq(EO::Guild::Tables::TOWN_UIDS['Solhaven'])
    expect(described_class::HOMES['Kharam-Dzu']).to eq(described_class::HOMES['Kharam Dzu'])
  end

  it 'recognises the child answer and the contact text' do
    expect('The child says, "Please, take me home to Icemule Trace!"').to match(described_class::CHILD_ANSWER)
    expect(described_class.contact?('You have made contact with the child you are to rescue and you must get him back alive.')).to be(true)
    expect(described_class.contact?('You have been tasked to rescue the young runaway son of a local citizen.')).to be(false)
  end

  it 'finds the child in the room, or gives up after the wait' do
    child = Struct.new(:id, :noun).new('123', 'child')
    stub_const('GameObj', Class.new { define_singleton_method(:npcs) { [child] } })
    expect(described_class.find_child).to eq('123')
    stub_const('GameObj', Class.new { def self.npcs = [] })
    expect(described_class.find_child(timeout: 0)).to be_nil
  end
end

RSpec.describe EO::Guild::Rescue::Walk do
  let(:npc) { Struct.new(:id, :name, keyword_init: true) }
  let(:room) { Struct.new(:id, :uid).new(28_978, [7_119_101]) }
  let(:npcs) { [] }
  let(:script) { Struct.new(:watchfor).new({}) }
  let(:walk) do
    described_class.new(child: 'B69', to: 28_978, points: [28_978], disablers: EO::Guild::Disablers::Policy.new(enabled: false))
  end

  before do
    here = room
    stub_const('Map', Class.new { define_singleton_method(:current) { here } })
    stub_const('Room', Map)
    present = npcs
    stub_const('GameObj', Class.new { define_singleton_method(:npcs) { present }; def self.room_desc = [] })
    running = script
    stub_const('Script', Class.new { define_singleton_method(:current) { running } })
    stub_const('Watchfor', Class.new { define_method(:initialize) { |line, &block| running.watchfor[line] = block } })
  end

  context 'one step at a time' do
    let(:start) { Struct.new(:id, :uid).new(30_850, [7_138_115]) }
    let(:here) { [start] }

    before do
      at = here
      stub_const('Map', Class.new { define_singleton_method(:current) { at.first } })
      stub_const('Room', Map)
      walk.define_singleton_method(:move) { at[0] = Struct.new(:id, :uid).new(28_978, [7_119_101]) }
      walk.define_singleton_method(:disable_hostiles) { nil }
    end

    it 'moves a room, then waits for the child however long it takes' do
      walk.start
      expect(walk.step).to eq(:moved)
      later = Time.now + 600
      allow(Time).to receive(:now).and_return(later)
      expect(walk.step).to eq(:waiting) # ten minutes on, still waiting
      npcs << npc.new(id: 'B69', name: 'a young giantman child')
      npcs << npc.new(id: 'A61', name: 'sentry Luthrek')
      asked = []
      walk.define_singleton_method(:fput) { |line| asked << line }
      expect(walk.step).to eq(:delivered)
      expect(asked).to eq(['ask #A61 about bounty'])
      walk.finish
      expect(script.watchfor).to be_empty
    end

    it 'goes back a room after a minute in the Logging Colony without the child, then on again' do
      log = Struct.new(:id, :uid).new(28_921, [589_001])
      at = here
      back = start
      walk.define_singleton_method(:move) { at[0] = log }
      went = []
      allow(EO).to receive(:go2) { |room| went << room; at[0] = back }
      walk.start
      expect(walk.step).to eq(:moved)
      expect(walk.step).to eq(:waiting)
      later = Time.now + 61
      allow(Time).to receive(:now).and_return(later)
      expect(walk.step).to eq(:unstuck)
      expect(went).to eq([30_850])
      expect(walk.step).to eq(:moved)
      expect(here.first.id).to eq(28_921)
    end

    it 'says the task failed on the way' do
      walk.start
      script.watchfor.values.first.call
      allow(EO).to receive(:go2)
      expect(walk.step).to eq(:failed)
    end
  end

  it 'hands the child over and removes its watch for a failed task' do
    npcs << npc.new(id: 'A61', name: 'sentry Luthrek')
    asked = []
    walk.define_singleton_method(:fput) { |line| asked << line }
    expect(walk.run).to eq(:delivered)
    expect(asked).to eq(['ask #A61 about bounty'])
    expect(script.watchfor).to be_empty
  end
end
