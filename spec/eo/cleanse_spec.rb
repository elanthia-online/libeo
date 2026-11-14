# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/cleanse/tables'
require_relative '../../scripts/eo/cleanse/hazards'
require_relative '../../scripts/eo/cleanse/traps'
require_relative '../../scripts/eo/cleanse/disarms'

RSpec.describe EO::Cleanse do
  include_context 'Lich mana'

  let(:spell_type) do
    Struct.new(:num, :known, :affordable, :casts, keyword_init: true) do
      def known? = known
      def affordable? = affordable
      def cast(arg = nil) = casts << arg
      def force_incant = casts << :incant
    end
  end
  let(:book) { Hash.new { |h, num| h[num] = spell_type.new(num: num, known: false, affordable: true, casts: []) } }
  let(:fputs) { [] }
  let(:replies) { [] }

  before do
    spells = book
    stub_const('Spell', Class.new { define_singleton_method(:[]) { |num| spells[num] } })
    log = fputs
    queue = replies
    [EO::Cleanse, EO::Cleanse::Hazards].each do |mod|
      mod.define_singleton_method(:fput) { |cmd| log << cmd }
      mod.define_singleton_method(:dothistimeout) { |cmd, *_| log << cmd && queue.shift }
    end
    allow(EO::Cleanse).to receive(:sleep)
  end

  after do
    [EO::Cleanse, EO::Cleanse::Hazards].each { |mod| %i[fput dothistimeout].each { |m| mod.singleton_class.remove_method(m) } }
  end

  it 'gives the first spell a character knows for a job' do
    expect(described_class.spell(:dispel)).to be_nil
    book[119].known = true
    book[1218].known = true
    expect(described_class.spell(:dispel).num).to eq(1218)
    expect(described_class.spell(:webs).num).to eq(1218)
  end

  it 'targets a hazard only on the answer that turns attention to it' do
    web = Struct.new(:id).new('7')
    replies.push('Suspecting that a kobold is the origin of the web, you turn your attention towards it!', 'You are unable to discern the origin of the web.', nil)
    expect([described_class.target(web), described_class.target(web), described_class.target(web)]).to eq([true, false, false])
    expect(fputs).to eq(['target #7'] * 3)
  end

  it 'remembers the latest bad targets, up to its size' do
    bad = described_class::BadTargets.new(2)
    %w[1 2 3].each { |id| bad << id }
    expect(%w[1 2 3].map { |id| bad.include?(id) }).to eq([false, true, true])
  end

  describe EO::Cleanse::Hazards do
    let(:web) { Struct.new(:id).new('7') }
    let(:skills) { { cleave: false, thieve: false, stamina: 50 } }

    before do
      state = skills
      stub_const('CMan', Class.new { define_singleton_method(:known?) { |name| state[name == 'Spell Cleave' ? :cleave : :thieve] } })
      stub_const('Char', Class.new { define_singleton_method(:stamina) { state[:stamina] } })
    end

    it 'casts the spell at the hazard when it can be afforded, asking for a mana pulse first' do
      spell = book[417]
      spell.known = true
      described_class.clear(web, spell)
      expect(spell.casts).to eq(['at #7'])
      spell.affordable = false
      described_class.clear(web, spell)
      expect(pulses).to eq([417, 417])
      expect(spell.casts.size).to eq(1)
    end

    it 'cleaves without a spell, thieves without cleave, and needs the stamina' do
      skills.merge!(cleave: true, thieve: true)
      described_class.clear(web, nil)
      skills[:cleave] = false
      described_class.clear(web, nil)
      skills[:stamina] = 9
      described_class.clear(web, nil)
      expect(fputs).to eq(['cman scleave #7', 'cman sthieve #7'])
    end

    it 'blows mist away by incanting 912, or casting 612 at it' do
      described_class.blow_away(web, book[912])
      described_class.blow_away(web, book[612])
      expect(book[912].casts).to eq([:incant])
      expect(book[612].casts).to eq(['at #7'])
    end

    it 'hits a runestone until it shatters, five swings at most' do
      swings = [['You bash the runestone.'], ['You bash it.', 'It crashes to the ground and shatters into pale dust.']]
      count = 0
      stub_const('Lich::Util', Class.new { define_singleton_method(:issue_command) { |*_, **| (count += 1) && (swings.shift || ['You bash it.']) } })
      stub_const('GameObj', Class.new { define_singleton_method(:loot) { [Struct.new(:id).new('7')] } })
      described_class.define_singleton_method(:waitrt?) { nil }
      described_class.shatter(web)
      expect(count).to eq(2)
      described_class.shatter(web)
      expect(count).to eq(7)
    ensure
      described_class.singleton_class.remove_method(:waitrt?)
    end
  end
end

RSpec.describe EO::Cleanse::Traps do
  include_context 'a script lending helpers'

  # a room is itself and no other, as a Room is: a Struct of the same id would be equal
  let(:room) { Class.new { attr_reader :id; def initialize(id) = @id = id } }
  let(:here) { [room.new(5)] }
  let(:state) { { dead: false, muckled: false } }

  before do
    current = here
    flags = state
    stub_const('Room', Class.new { define_singleton_method(:current) { current.first } })
    described_class.define_singleton_method(:dead?) { flags[:dead] }
    described_class.define_singleton_method(:muckled?) { flags[:muckled] }
  end

  after { %i[dead? muckled?].each { |m| described_class.singleton_class.remove_method(m) } }

  it 'knows the trap room by id, and never takes two unmapped rooms for one' do
    expect(described_class.here?(room.new(5))).to be(true)
    expect(described_class.here?(room.new(6))).to be(false)
    expect(described_class.here?(nil)).to be(false)
    here[0] = room.new(nil)
    expect(described_class.here?(room.new(nil))).to be(false)
    expect(described_class.here?(here.first)).to be(true)
  end

  it 'searches until the roll succeeds' do
    answers['search'] = [['d100: 12  Failure!'], ['d100: 88  Success!']]
    expect(described_class.search(room.new(5))).to eq(:found)
    expect(sent).to eq([:wait, 'search', :wait, 'search'])
  end

  it 'says why a search ended without a find' do
    answers['search'] = [["You don't find anything of interest here."], ["You can't see well enough to search around."]]
    expect(described_class.search(room.new(5))).to eq(:clear)
    expect(described_class.search(room.new(5))).to eq(:blind)
    expect(described_class.search(room.new(6))).to eq(:moved)
    state[:muckled] = true
    expect(described_class.search(room.new(5))).to eq(:muckled)
  end

  it 'gives up a search after three tries' do
    expect(described_class.search(room.new(5))).to eq(:exhausted)
    expect(sent.count('search')).to eq(3)
  end

  it 'disarms until it succeeds or there is nothing to disarm, three tries at most' do
    answers['disarm apparatus'] = [['d100: 3  Failure!'], ['You want to disarm what?']]
    described_class.disarm(room.new(5))
    expect(sent.count('disarm apparatus')).to eq(2)
    sent.clear
    described_class.disarm(room.new(5))
    expect(sent.count('disarm apparatus')).to eq(3)
  end

  it 'picks the nearer of the nearest town and sanctuary to wait out the curse' do
    place = Class.new do
      def dijkstra = [{}, { 10 => 30, 20 => 12 }]
      def find_nearest_by_tag(tag) = { 'town' => 10, 'sanctuary' => 20 }[tag]
    end.new
    stub_const('Room', Class.new { define_singleton_method(:current) { place } })
    expect(described_class.safe_place).to eq(20)
  end
end

RSpec.describe EO::Cleanse::Disarms do
  let(:thing) { Struct.new(:id, :name, :noun) }
  let(:hands) { { right: thing.new('1', 'broadsword', 'broadsword'), left: thing.new(nil, 'Empty', nil) } }
  let(:saved) { [nil] }

  before do
    held = hands
    store = saved
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
    end)
    stub_const('UserVars', Class.new do
      define_singleton_method(:last_disarm) { store.first }
      define_singleton_method(:last_disarm=) { |value| store[0] = value }
    end)
    stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:id, :title).new(100, ['[Town Square]']) } })
  end

  it 'knows a weapon is back by a new thing in hand, of the noun lost when given' do
    expect(described_class.recovered?(['1'])).to be(false)
    hands[:left] = thing.new('9', 'steel dagger', 'dagger')
    expect(described_class.recovered?(['1'])).to be(true)
    expect(described_class.recovered?(['1'], 'Dagger')).to be(true)
    expect(described_class.recovered?(['1'], 'falchion')).to be(false)
    expect(described_class.held_ids).to eq(%w[1 9])
  end

  it 'reads anything but a list as no disarms' do
    saved[0] = 4521
    expect(described_class.list).to eq([])
  end

  it 'adds a disarm with where and when, keeping the latest twenty' do
    id = described_class.add('falchion')
    entry = described_class.list.first
    expect(entry).to include(id: id, item: 'falchion', room: 100, title: '[Town Square]')
    expect(described_class.tracked?(id)).to be(true)
    25.times { described_class.add('dagger') }
    expect(described_class.list.size).to eq(20)
    expect(described_class.tracked?(id)).to be(false)
  end

  it 'removes one, or everything saved for a room the game says is empty' do
    first = described_class.add('falchion')
    second = described_class.add('dagger')
    described_class.remove(first)
    expect(described_class.list.map { |e| e[:id] }).to eq([second])
    described_class.add('mace')
    described_class.remove_room(100, second)
    expect(described_class.list).to be_empty
  end

  it 'keeps the others when the room has no id' do
    first = described_class.add('falchion')
    saved[0].first[:room] = nil
    second = described_class.add('dagger')
    saved[0].last[:room] = nil
    described_class.remove_room(nil, second)
    expect(described_class.list.map { |e| e[:id] }).to eq([first])
  end

  it 'drops the entry for what a search turned up instead' do
    described_class.add('falchion')
    described_class.add('dagger')
    described_class.remove_found('a steel dagger', 100)
    expect(described_class.list.map { |e| e[:item] }).to eq(['falchion'])
  end

  it 'reads what RECOVER ITEM picked up, with or without XML' do
    expect(described_class.spied_item(['You spy a <a exist="5" noun="falchion">vultite falchion</a> and recover it!'])).to eq('falchion')
    expect(described_class.spied_item(['You spy a vultite falchion and recover it!'])).to eq('a vultite falchion')
    expect(described_class.spied_item(['You search around.'])).to be_nil
  end
end
