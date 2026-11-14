# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/cleanse/tables'
require_relative '../../scripts/eo/cleanse/afflictions'
require_relative '../../scripts/eo/cleanse/disarms'
require_relative '../../scripts/eo/cleanse/recovery'

RSpec.describe EO::Cleanse::Afflictions do
  include_context 'a script lending helpers'
  include_context 'Lich mana'

  let(:spell_type) do
    Struct.new(:num, :known, :affordable, :available, :active, :casts, keyword_init: true) do
      def known? = known
      def affordable? = affordable
      def available? = available
      def active? = active
      def cast(arg = nil) = casts << arg
      def force_incant(arg) = casts << [:incant, arg]
    end
  end
  let(:book) { Hash.new { |h, num| h[num] = spell_type.new(num: num, known: false, affordable: true, available: true, active: false, casts: []) } }
  let(:fputs) { [] }
  let(:state) { { stamina: 50, debuffs: [], disease: [true, true, false], standing: true } }

  before do
    spells = book
    now = state
    log = fputs
    stub_const('Spell', Class.new { define_singleton_method(:[]) { |num| spells[num] } })
    stub_const('Char', Class.new { define_singleton_method(:stamina) { now[:stamina] } })
    stub_const('Effects::Debuffs', Class.new { define_singleton_method(:active?) { |name| now[:debuffs].include?(name) } })
    stub_const('Effects::Buffs', Class.new { define_singleton_method(:active?) { |_name| false } })
    stub_const('Effects::Cooldowns', Class.new { define_singleton_method(:active?) { |_name| false } })
    stub_const('XMLData', Class.new { define_singleton_method(:current_target_id) { '77' } })
    described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    described_class.define_singleton_method(:checkstanding) { now[:standing] }
    described_class.define_singleton_method(:checkdisease) { now[:disease].shift }
  end

  after { %i[fput checkstanding checkdisease].each { |m| described_class.singleton_class.remove_method(m) } }

  it 'casts 113 until the disease is gone' do
    described_class.cure_disease
    expect(book[113].casts.size).to eq(2)
    expect(sent).to eq(%i[wait wait])
  end

  it 'retreats from a root or press with the stamina, and takes the target up again' do
    state[:debuffs] = ['Rooted']
    told = []
    described_class.retreat(before: -> { told << :pause })
    expect(told).to eq([:pause])
    expect(fputs).to eq(['target clear', 'cman retreat', 'target #77'])
    state[:stamina] = 10
    described_class.retreat
    expect(fputs.size).to eq(3)
  end

  it 'opens a channel of the dispel for each debuff that is on the character' do
    state[:debuffs] = %w[Vertigo Mindwipe]
    dispel = book[417]
    described_class.dispel_debuffs(dispel)
    expect(dispel.casts).to eq([[:incant, 'channel open']] * 2)
  end

  describe 'a stun' do
    let(:cman) { { 'Berserk' => true, 'Stun Maneuvers' => 5 } }

    before do
      known = cman
      stub_const('CMan', Class.new do
        define_singleton_method(:available?) { |name, min_rank: 1| known[name] == true || known[name].to_i >= min_rank }
        define_singleton_method(:use) { |*_args| nil }
      end)
      stub_const('Skills', Class.new { define_singleton_method(:slblessings) { 20 } })
      described_class.define_singleton_method(:checkroom) { |_name| nil }
      described_class.define_singleton_method(:checkhidden) { false }
    end

    after { %i[checkroom checkhidden].each { |m| described_class.singleton_class.remove_method(m) } }

    it 'has only the means allowed and ready' do
      book[1040].known = true
      means = described_class.stun_means(stunned1040: true, berserk: true, flee: true)
      expect(means.select { |_k, v| v }.keys).to contain_exactly(:stunned1040, :berserk, :flee)
    end

    it 'leaves the combat maneuvers out when swallowed' do
      described_class.define_singleton_method(:checkroom) { |name| name == 'Ooze, Innards' ? name : nil }
      means = described_class.stun_means(berserk: true, hide: true)
      expect(means.values.any?).to be(false)
    end

    it 'shouts 1040 before it beseeches' do
      described_class.break_stun(stunned1040: true, beseech: true)
      described_class.break_stun(beseech: true)
      expect(fputs).to eq(['shout 1040', 'beseech'])
    end
  end

  describe 'a web' do
    before do
      stub_const('CMan', Class.new { define_singleton_method(:available?) { |_name| false } })
      stub_const('Feat', Class.new { define_singleton_method(:available?) { |*_, **| false } })
    end

    it 'has a way out with 1040 known and affordable, and shouts it' do
      expect(described_class.web_escape?(berserk: false, beseech: false)).to be(false)
      book[1040].known = true
      expect(described_class.web_escape?(berserk: false, beseech: false)).to be(true)
      described_class.break_web(berserk: false, beseech: false)
      expect(fputs).to eq(['shout 1040'])
    end

    it 'goes berserk only when allowed' do
      allow(CMan).to receive(:available?).and_return(true)
      allow(described_class).to receive(:berserk)
      book[1635].known = true
      described_class.break_web(berserk: false, beseech: true)
      expect(described_class).not_to have_received(:berserk)
      described_class.break_web(berserk: true, beseech: true)
      expect(described_class).to have_received(:berserk).once
      expect(fputs).to eq(['beseech'])
    end

    it 'beseeches only when allowed' do
      book[1635].known = true
      described_class.break_web(berserk: false, beseech: false)
      described_class.break_web(berserk: false, beseech: true)
      expect(fputs).to eq(['beseech'])
    end
  end

  it 'quiets the room with the first spell allowed and known' do
    stub_const('GameObj', Class.new { define_singleton_method(:npcs) { [] } })
    book[619].known = true
    book[709].known = true
    described_class.settle_room(use_140: true, use_619: true, use_709: true)
    described_class.settle_room(use_709: true)
    expect(book[619].casts.size).to eq(1)
    expect(book[709].casts.size).to eq(1)
    expect(book[140].casts).to be_empty
  end
end

RSpec.describe EO::Cleanse::Recovery do
  include_context 'a script lending helpers'
  include_context 'Lich mana'

  let(:thing) { Struct.new(:id, :name, :noun) }
  let(:hands) { { right: thing.new(nil, 'Empty', nil), left: thing.new(nil, 'Empty', nil) } }
  let(:saved) { [[{ id: 'a1', item: 'falchion', room: 100 }]] }
  let(:fputs) { [] }
  let(:emptied) { [0] }

  before do
    held = hands
    store = saved
    log = fputs
    count = emptied
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
    end)
    stub_const('UserVars', Class.new do
      define_singleton_method(:last_disarm) { store.first }
      define_singleton_method(:last_disarm=) { |value| store[0] = value }
    end)
    stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:id).new(100) } })
    EO.use(script: 'spec', say: ->(type, text) { said << [type, text] })
    described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    described_class.define_singleton_method(:empty_hands) { count[0] += 1 }
    described_class.define_singleton_method(:kneeling?) { true }
  end

  after { %i[fput empty_hands kneeling?].each { |m| described_class.singleton_class.remove_method(m) } }

  def search = described_class.search(item: 'falchion', known_ids: [], room_id: 100, disarm_id: 'a1')

  it 'stops at the weapon and drops it from the list' do
    answers['recover item'] = ['You spy a <a exist="5" noun="falchion">vultite falchion</a> and recover it!']
    expect(search).to eq(1)
    expect(saved.first).to be_empty
    expect(went).to eq([100])
    expect(sent).to eq(['recover item', :wait])
  end

  it 'goes on searching after turning up something else, and says so' do
    answers['recover item'] = [['You spy a <a exist="6" noun="dagger">steel dagger</a> and recover it!'],
                               ['You spy a <a exist="5" noun="falchion">vultite falchion</a> and recover it!']]
    search
    expect(said.first.last).to eq(' Recovered dagger while looking for falchion. Still searching.')
    expect(sent.count('recover item')).to eq(2)
  end

  it 'stops tracking the room when the game says nothing is there' do
    answers['recover item'] = ['You find nothing recoverable.']
    search
    expect(saved.first).to be_empty
    expect(said.first.last).to include('Nothing to recover in room 100')
  end

  it 'empties the hands again when told to, and counts it' do
    answers['recover item'] = [['In order to recover something, your hands must be empty.'], ['You find nothing recoverable.']]
    expect(search).to eq(2)
    expect(emptied.first).to eq(2)
  end

  it 'gives up after ten searches' do
    answers['recover item'] = ['You continue to intently search the area.']
    search
    expect(sent.count('recover item')).to eq(10)
    expect(saved.first.size).to eq(1)
  end

  it 'pries until the weapon comes free, ten times at most' do
    answers['pry my falchion'] = [['You try to pry your falchion free.'], ['You pry your falchion free from the webbing!']]
    expect(described_class.pry('falchion')).to be(true)
    expect(described_class.pry('falchion')).to be(false)
    expect(sent.count('pry my falchion')).to eq(12)
  end

  it 'stops the calming spells it was told were cast' do
    described_class.stop_calm([true, false])
    described_class.stop_calm([false, true])
    expect(fputs).to eq(['stop 213', 'stop 1011'])
  end

  it 'clenches until the weapon is grabbed' do
    answers['clench maw'] = [['Nothing happens.'], ['You reach up and grab your falchion!']]
    described_class.clench('maw')
    expect(sent).to eq(['clench maw', :wait, 'clench maw', :wait])
  end
end
