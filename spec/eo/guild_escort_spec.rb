# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/guild/escort'
require_relative '../../scripts/eo/guild/escort_routes'

# Lich's Numeric#as_time, as far as a path's estimate needs it.
Numeric.class_eval { def as_time = format('%.1f', self) } unless Numeric.method_defined?(:as_time)

RSpec.describe EO::Guild::Escort do
  let(:npc) { Struct.new(:id, :name, :noun, :status, :type) }
  let(:room_type) { Struct.new(:id, :wayto, :timeto) }
  let(:log) { [] }
  let(:state) { { hidden: false, room: nil, npcs: [], pcs: [], loot: [], count: 1, answers: {}, moves: {}, running: [] } }

  # Stands in for the Lich methods a walk calls, on one object.
  def lich(obj)
    now = state
    out = log
    {
      fput: ->(cmd) { out << cmd },
      hidden?: -> { now[:hidden] }, invisible?: -> { false }, muckled?: -> { false },
      waitrt?: -> {}, waitcastrt?: -> {}, sleep: ->(_t) {}, checkrt: -> { 0 }, checkcastrt: -> { 0 },
      echo: ->(text) { out << [:echo, text.to_s] }, respond: ->(text) { out << [:respond, text] },
      mana: -> { 200 }, clear: -> { [] }, puts: ->(_text) {}, monsterbold_start: -> { "" }, monsterbold_end: -> { "" },
      move: lambda { |way|
        out << [:move, way]
        to = now[:moves][way]
        to == false ? false : (now[:room] = to if to)
      },
      dothistimeout: lambda { |cmd, _time, _pattern|
        out << cmd
        now[:answers][now[:answers].keys.find { |k| cmd =~ k }]
      },
      start_script: lambda { |name, args = [], _opts = {}|
        out << [:script, name, args]
        now[:npcs].clear
      },
      wait_while: ->(&_block) {}, running?: ->(_name) { false }, pause_script: -> { out << :pause && now[:npcs].clear }
    }.each { |name, body| obj.define_singleton_method(name, &body) }
    obj
  end

  def lich_names = lich(Object.new).singleton_methods

  before do
    now = state
    stub_const('GameObj', Class.new do
      define_singleton_method(:npcs) { now[:npcs].empty? ? nil : now[:npcs] }
      define_singleton_method(:pcs) { now[:pcs].empty? ? nil : now[:pcs] }
      define_singleton_method(:loot) { now[:loot].empty? ? nil : now[:loot] }
    end)
    stub_const('Room', Class.new do
      define_singleton_method(:current) { now[:room] }
      define_singleton_method(:[]) { |_id| Struct.new(:timeto).new({}) }
    end)
    stub_const('XMLData', Class.new do
      define_singleton_method(:room_count) { now[:count] }
      define_singleton_method(:game) { 'GSIV' }
    end)
    stub_const('Char', Class.new { define_singleton_method(:name) { 'Nisugi' } })
    stub_const('UserVars', Class.new { define_singleton_method(:attacked_me) { nil } })
    stub_const('Spell', Class.new do
      define_singleton_method(:lock_cast) {}
      define_singleton_method(:unlock_cast) {}
    end)
    $ego2_my_ambush = false
  end

  after { $ego2_my_ambush = nil }

  def walk(hide: false, haste: false, poach: false, attack_script: 'bigshot', targetable: [], untargetable: [])
    lich(EO::Guild::Escort::Walk.new(hide: hide, haste: haste, poach: poach, attack_script: attack_script,
                                     targetable: targetable, untargetable: untargetable))
  end

  it 'reads where to wait and the town to reach from the task' do
    text = 'The taskmaster told you: "A certain client has hired us to provide a protective escort on her upcoming journey.  ' \
           "Go to the area just inside the North Gate and WAIT for her to meet you there.  You must guarantee her safety to Ta'Illistim as soon as you can, " \
           'being ready for any dangers that the two of you may face.  Good luck!"'
    expect(described_class.task(text)).to eq(['area just inside the North Gate', "Ta'Illistim"])
    expect(described_class.task('You are not currently assigned a task.')).to be_nil
  end

  it 'knows a drop-off and the fares between any two of the towns a client is met in' do
    towns = described_class::PICKUPS.values.map(&:first)
    expect(described_class::DROPOFFS.keys).to match_array(towns)
    towns.each { |town| expect(described_class::TRAVEL_COST[town].keys).to match_array(towns - [town]) }
  end

  describe '.nearest' do
    before do
      state[:room] = room_type.new(5)
      stub_const('Map', Class.new { define_singleton_method(:dijkstra) { |_from, _to| [{}, { 7 => 30, 9 => 12 }] } })
    end

    it 'is the room stood in, when that is one of them' do
      expect(described_class.nearest([9, 5])).to eq(5)
    end

    it 'is the quickest to reach, and none when none can be reached' do
      expect(described_class.nearest([7, 9, 11])).to eq(9)
      expect(described_class.nearest([11])).to be_nil
    end
  end

  it 'comes out of hiding to tell a client to follow, and knows a client who is not this one' do
    lich(described_class)
    state[:hidden] = true
    client = npc.new('8', 'a human merchant', 'merchant')
    state[:answers][/tell #8/] = 'The merchant nods and says to you, "Lead on."'
    expect(described_class.follow(client)).to be(true)
    state[:answers][/tell #8/] = %(The merchant says to you, "The guild didn't hire you to guide me.")
    expect(described_class.follow(client)).to be(false)
    expect(log).to eq(['unhide', 'tell #8 to follow', 'unhide', 'tell #8 to follow'])
  ensure
    lich_names.each { |m| described_class.singleton_class.remove_method(m) }
  end

  it 'names the escorting script in the ambush watch' do
    watch = described_class.ambush_watch('escortgo2')
    expect(watch).to include('running?("escortgo2")', '$ego2_my_ambush = true', "\#{$ego2_escort_id}")
  end

  it 'has a route for each hard part of the roads, keyed by the rooms it joins' do
    expect(described_class::ROUTES.size).to eq(87)
    expect(described_class::ROUTES.keys).to all(match(/^\d+,\d+$/))
    kinds = described_class::ROUTES.values.map(&:first).uniq
    expect(kinds).to all(satisfy { |kind| described_class::Walk.private_method_defined?(:"route_#{kind}") })
  end

  describe EO::Guild::Escort::Walk do
    describe '#hide' do
      before { state[:room] = room_type.new(100) }

      it 'hides when hiding is wanted' do
        walk(hide: true).hide
        expect(log).to eq(['hide'])
      end

      it 'does nothing when it is not, when hidden, or in a room not to hide in' do
        walk(hide: false).hide
        state[:hidden] = true
        walk(hide: true).hide
        state[:hidden] = false
        state[:room] = room_type.new(1155)
        walk(hide: true).hide
        expect(log).to be_empty
      end
    end

    describe '#check_room' do
      let(:orc) { npc.new('3', 'a greater orc', 'orc', nil, 'aggressive npc') }

      it 'tries a creature not met before, and remembers what TARGET said' do
        known = []
        never = []
        state[:npcs] = [orc, npc.new('4', 'a town guard', 'guard')]
        state[:answers][/target #3/] = 'You are now targeting a greater orc.'
        state[:answers][/target #4/] = "You can't target a town guard."
        walk(targetable: known, untargetable: never).check_room
        expect(known).to eq(['a greater orc'])
        expect(never).to eq(['a town guard'])
      end

      it 'runs the attack script against a creature able to attack' do
        state[:npcs] = [orc]
        walk(targetable: ['a greater orc']).check_room
        expect(log).to eq([[:script, 'bigshot', ['3']]])
      end

      it 'pauses for the player when there is no attack script' do
        state[:npcs] = [orc]
        walk(attack_script: nil, targetable: ['a greater orc']).check_room
        expect(log).to eq([:pause])
      end

      it 'leaves alone the client, a creature of no account, and one that is down' do
        state[:npcs] = [npc.new('8', 'a human merchant', 'merchant'), npc.new('5', 'kobold', 'kobold'),
                        npc.new('6', 'a greater orc', 'orc', 'stunned')]
        walk(targetable: ['a human merchant', 'kobold', 'a greater orc']).check_room
        expect(log).to be_empty
      end

      it 'leaves a room another character is in, unless the ambush is its own or it may poach' do
        state[:pcs] = [Struct.new(:noun, :status).new('Someone', nil)]
        state[:npcs] = [orc]
        walk(targetable: ['a greater orc']).check_room
        expect(log).to be_empty

        $ego2_my_ambush = true
        walk(targetable: ['a greater orc']).check_room
        state[:npcs] = [orc]
        $ego2_my_ambush = false
        walk(poach: true, targetable: ['a greater orc']).check_room
        expect(log.size).to eq(2)
      end

      it 'fights its own bandits though they are down, but never the dead' do
        $ego2_my_ambush = true
        state[:npcs] = [npc.new('6', 'a bandit', 'bandit', 'prone', 'bandit'), npc.new('7', 'a bandit', 'bandit', 'dead', 'bandit')]
        walk(targetable: ['a bandit']).check_room
        expect(log).to eq([[:script, 'bigshot', ['6']]])
      end
    end

    describe '#step' do
      let(:here) { room_type.new(10, { '11' => 'north' }, {}) }
      let(:there) { room_type.new(11, {}, {}) }

      before do
        state[:room] = here
        state[:moves]['north'] = there
        stub_const('Map', Class.new do
          define_singleton_method(:dijkstra) { |_from, _to| [{ 12 => 11, 11 => 10 }, { 12 => 6.4 }] }
        end)
      end

      def bound_for(id, **)
        walk(**).tap { |w| w.destination = room_type.new(id) }
      end

      it 'lays the path, tells how long it should take, and goes the way the map gives' do
        w = bound_for(12)
        expect(w.step).to eq(:moved)
        expect(w.path).to eq([10, 11, 12])
        expect(log).to eq([[:respond, 'ETA: 0.2 (3 rooms to move through).'], [:move, 'north']])
        expect($go2_use_portals).to be(false)
      end

      it 'answers that no path leads there, or that the room is unmapped' do
        expect(bound_for(99).step).to eq(:unreachable)
        state[:room] = nil
        expect(bound_for(12).step).to eq(:unmapped)
      end

      it 'takes a way out of the map that fails six times' do
        state[:moves]['north'] = false
        bound_for(12).step
        expect(log.count([:move, 'north'])).to eq(6)
        expect(here.wayto).to be_empty
      end

      it 'sneaks through the caves until the room changes, standing first' do
        w = walk
        sent = log
        state[:answers][/southwest/] = 'Trying to sneak over the rubble...'
        w.define_singleton_method(:standing?) { false }
        allow(XMLData).to receive(:room_count) { sent.count('southwest') < 2 ? 1 : 2 }
        w.take_route(:sneak, 'southwest')
        expect(log).to eq(%w[stand southwest stand southwest])
      end

      it 'catches the client up between the moves of a road in steps' do
        w = walk
        seen = 0
        w.define_singleton_method(:escort_here?) { (seen += 1) > 2 }
        w.take_route(:steps, 'south', 'west')
        expect(log).to eq([[:move, 'south'], [:move, 'west']])
        expect(seen).to eq(3)
      end

      it 'takes its own route where it has one' do
        state[:room] = room_type.new(2524, { '2523' => 'east' }, {})
        stub_const('Map', Class.new { define_singleton_method(:dijkstra) { |_from, _to| [{ 2523 => 2524 }, { 2523 => 1 }] } })
        bound_for(2523, hide: true).step
        expect(log.last(2)).to eq([[:move, 'climb rockslide'], 'hide'])
      end

      it 'goes back a room for a client who did not follow' do
        w = bound_for(12)
        w.step
        there.wayto['10'] = 'south'
        state[:moves]['south'] = here
        expect(w.backtrack).to eq(:moved)
        expect(log.last).to eq([:move, 'south'])
      end
    end
  end
end
