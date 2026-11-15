# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/guild/disablers'
require_relative '../../scripts/eo/guild/rescue'

RSpec.describe EO::Guild::Disablers do
  let(:spell_type) do
    Struct.new(:num, :known, :mana_cost, :active, :log) do
      def known? = known
      def affordable? = true
      def active? = active
      def cast = log << [:cast, num]
    end
  end
  let(:log) { [] }
  let(:known) { { 201 => 1, 213 => 13, 410 => 10, 501 => 1, 505 => 5, 1011 => 11 } }
  let(:targets) { [] }
  let(:state) { { lore: 0, justice: false, song: false } }
  let(:creature) { Struct.new(:name, :status) }

  before do
    book = known
    out = log
    now = state
    here = targets
    type = spell_type
    stub_const('Spell', Class.new do
      define_singleton_method(:[]) { |num| type.new(num, book.key?(num), book[num].to_i, num == 1011 && now[:song], out) }
    end)
    stub_const('Skills', Class.new { define_singleton_method(:elair) { now[:lore] } })
    stub_const('GameObj', Class.new do
      define_singleton_method(:targets) { here }
      define_singleton_method(:npcs) { here }
    end)
    described_class.define_singleton_method(:mana) { 50 }
    described_class.define_singleton_method(:fput) { |cmd| out << cmd }
    allow(described_class).to receive(:can_cast?).and_return(true)
    allow(described_class).to receive(:justice?) { now[:justice] }
  end

  after { %i[mana fput].each { |m| described_class.singleton_class.remove_method(m) } }

  def best(**) = described_class.best(min_mana: 0, custom: false, untargetable: [], **)

  it 'counts Call Wind for the whole room from twenty ranks of air lore' do
    wind = -> { described_class.table.find { |d| d[:num] == 504 }[:single_target] }
    expect(wind.call).to be(true)
    state[:lore] = 20
    expect(wind.call).to be(false)
  end

  it 'chooses nothing when the character cannot cast, unless told not to ask' do
    targets << creature.new('a kobold')
    allow(described_class).to receive(:can_cast?).and_return(false)
    expect(best).to be_nil
    expect(best(skip_can_cast: true)).not_to be_nil
  end

  it 'chooses the cheapest spell fit for one creature' do
    targets << creature.new('a kobold')
    expect(best[:num]).to eq(201).or eq(501)
    targets.replace([creature.new('a construct ghost')])
    expect(best[:num]).to eq(505)
  end

  it 'keeps mana back' do
    targets << creature.new('a kobold')
    expect(described_class.best(min_mana: 45, custom: false, untargetable: [])[:num]).to eq(201).or eq(501)
    expect(described_class.best(min_mana: 50, custom: false, untargetable: [])).to be_nil
  end

  it 'takes Sanctuary or Song of Peace for more than one, at any cost' do
    targets.push(creature.new('a kobold'), creature.new('a kobold'))
    expect(best[:num]).to eq(213)
  end

  it 'does not count a creature that is down, or one known to be untargetable' do
    targets.push(creature.new('a kobold'), creature.new('a kobold', 'stunned'), creature.new('a statue'))
    expect(described_class.best(min_mana: 0, custom: false, untargetable: ['a statue'])[:num]).to eq(201).or eq(501)
  end

  it 'keeps to spells safe in town where there is justice' do
    known.replace(410 => 10, 213 => 13)
    targets << creature.new('a kobold')
    expect(best[:num]).to eq(410)
    state[:justice] = true
    expect(best[:num]).to eq(213)
  end

  it 'takes the custom spell whenever it is known' do
    targets << creature.new('a kobold')
    expect(described_class.best(min_mana: 0, custom: 505, untargetable: [])).to eq({ num: 505 })
    expect(described_class.best(min_mana: 0, custom: 619, untargetable: [])[:num]).to eq(201).or eq(501)
  end

  it 'casts, and says whether it was Song of Peace, renewing one that is up' do
    expect(described_class.cast({ num: 201 })).to be(false)
    expect(described_class.cast({ num: 1011 })).to be(true)
    state[:song] = true
    described_class.cast({ num: 1011 })
    expect(log).to eq([[:cast, 201], 'spell active', [:cast, 1011], 'spell active', 'renew 1011'])
  end

  it 'targets at random and waits for what the game says' do
    lines = ['A kobold arrives.', 'Could not find a valid target.', 'You are now targeting a kobold.']
    described_class.define_singleton_method(:put) { |_cmd| nil }
    described_class.define_singleton_method(:get) { lines.shift }
    expect(described_class.target_random).to be(false)
    expect(described_class.target_random).to be(true)
  ensure
    %i[put get].each { |m| described_class.singleton_class.remove_method(m) }
  end
end

RSpec.describe EO::Guild::Rescue do
  let(:npc) { Struct.new(:id, :name, :noun) }
  let(:state) { { npcs: [], targets: [], desc: [], pcs: nil, room: 1, answers: [] } }
  let(:log) { [] }

  before do
    now = state
    out = log
    stub_const('GameObj', Class.new do
      define_singleton_method(:npcs) { now[:npcs].empty? ? nil : now[:npcs] }
      define_singleton_method(:targets) { now[:targets] }
      define_singleton_method(:room_desc) { now[:desc] }
    end)
    stub_const('Map', Class.new do
      define_singleton_method(:current) { Struct.new(:id).new(now[:room]) }
      define_singleton_method(:ids_from_uid) { |uid| [uid % 1000] }
    end)
    {
      checkpcs: -> { now[:pcs] }, standing?: -> { true }, sleep: ->(_t) {}, echo: ->(text) { out << text },
      wait_while: ->(&_block) {}, fput: ->(cmd) { out << cmd }, waitrt?: -> {},
      dothistimeout: lambda { |cmd, _time, _pattern|
        out << cmd
        now[:answers].shift
      }
    }.each { |name, body| described_class.define_singleton_method(name, &body) }
  end

  after do
    %i[checkpcs standing? sleep echo wait_while fput waitrt? dothistimeout].each { |m| described_class.singleton_class.remove_method(m) }
  end

  it 'finds the child in the room' do
    expect(described_class.child).to be_nil
    state[:npcs] = [npc.new('3', 'a kobold', 'kobold'), npc.new('4', 'a lost child', 'child')]
    expect(described_class.child).to eq('4')
    expect(described_class.here('4').name).to eq('a lost child')
    expect(described_class.here('9')).to be_nil
  end

  it 'asks the child where it lives' do
    state[:answers] = [%(The child says, "Please, take me home to Wehnimer's Landing!"), nil]
    expect(described_class.ask_home).to eq("Wehnimer's Landing")
    expect(described_class.ask_home).to be_nil
    expect(described_class.homes).to include("Wehnimer's Landing", 'Kharam Dzu', 'Kharam-Dzu')
  end

  describe '.threat?' do
    let(:kid) { npc.new('4', 'a lost child', 'child') }
    let(:orc) { npc.new('3', 'a greater orc', 'orc') }

    before do
      state[:npcs] = [kid, orc]
      state[:targets] = [orc]
    end

    it 'is a creature to target in a room with nobody else' do
      expect(described_class.threat?('4', [])).to be(true)
    end

    it 'is not one known to be untargetable' do
      expect(described_class.threat?('4', ['a greater orc'])).to be(false)
    end

    it 'is not anything in a room with another character, a guard, or a purser' do
      state[:pcs] = ['Someone']
      expect(described_class.threat?('4', [])).to be(false)
      state[:pcs] = nil
      state[:npcs] << npc.new('5', 'a Town Guard', 'guard')
      expect(described_class.threat?('4', [])).to be(false)
      state[:npcs].pop
      state[:desc] = [npc.new('6', 'a grizzled purser', 'purser')]
      expect(described_class.threat?('4', [])).to be(false)
    end

    it 'is not the child alone' do
      state[:npcs] = [kid]
      state[:targets] = [kid]
      expect(described_class.threat?('4', [])).to be(false)
    end
  end

  it 'finds who to report to, among the creatures or in the room itself' do
    expect(described_class.reportee).to be_nil
    state[:desc] = [npc.new('6', 'a grizzled purser', 'purser')]
    expect(described_class.reportee.id).to eq('6')
    state[:npcs] = [npc.new('5', 'a Town Guard', 'guard')]
    expect(described_class.reportee.id).to eq('5')
  end

  describe '.climb_root' do
    it 'climbs out, trying again after a slip' do
      state[:answers] = ['You step into the root, but can see no way to climb the slippery tendrils inside.  After a moment, you step back out.',
                         'Suddenly, rootlike tendrils as thick as your thumb snake out and encircle you.']
      expect(described_class.climb_root).to eq(:out)
      expect(log).to eq(['go root', 'go root'])
    end

    it 'answers when this root will not be climbed now' do
      state[:answers] = ["There doesn't seem to be any way to do that at the moment."]
      expect(described_class.climb_root).to eq(:refused)
    end

    it 'gives up after three tries without an answer' do
      expect(described_class.climb_root).to eq(:failed)
      expect(log.count('go root')).to eq(3)
    end
  end

  it 'gives each root of the labyrinth the room to try next' do
    exits = described_class.maaghara_exits
    expect(exits.size).to eq(5)
    expect(exits.values - exits.keys).to be_empty
  end
end
