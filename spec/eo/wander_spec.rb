# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/wander'

RSpec.describe EO::Wander do
  let(:npc) { Struct.new(:id, :name, :noun, :status) }
  let(:state) { { npcs: [], targets: [], loot: [], room: nil, title: '[Somewhere]', game: 'GSIV', exits: [], moves: {}, look: nil } }
  let(:log) { [] }

  before do
    now = state
    out = log
    stub_const('GameObj', Class.new do
      define_singleton_method(:npcs) { now[:npcs].empty? ? nil : now[:npcs] }
      define_singleton_method(:targets) { now[:targets] }
      define_singleton_method(:loot) { now[:loot].empty? ? nil : now[:loot] }
    end)
    stub_const('Room', Class.new { define_singleton_method(:current) { now[:room] } })
    stub_const('XMLData', Class.new do
      define_singleton_method(:game) { now[:game] }
      define_singleton_method(:room_exits) { now[:exits] }
    end)
    {
      fput: ->(cmd) { out << cmd }, waitrt?: -> {}, sleep: ->(time) { out << [:sleep, time] },
      checkroom: -> { now[:title] }, wait_while: ->(&_block) {}, status_tags: -> {},
      dothistimeout: ->(_cmd, _time, _pattern) { now[:look] },
      move: lambda { |way|
        out << [:move, way]
        to = now[:moves][way]
        to == false ? false : (now[:room] = to if to)
      }
    }.each { |name, body| described_class.define_singleton_method(name, &body) }
    $wander_rooms = nil
    $mapdb_confluence_wayto = nil
    $mapdb_confluence_last_dir = nil
  end

  after do
    %i[fput waitrt? sleep checkroom wait_while status_tags dothistimeout move].each { |m| described_class.singleton_class.remove_method(m) }
    $wander_rooms = $mapdb_confluence_wayto = $mapdb_confluence_last_dir = nil
    $mapdb_confluence_hot_pit = $mapdb_confluence_cold_tranquility = nil
  end

  describe '.find_target' do
    it 'finds a live creature by name, the earlier name first' do
      state[:npcs] = [npc.new('1', 'a kobold', 'kobold'), npc.new('2', 'a greater orc', 'orc'), npc.new('3', 'a lesser orc', 'orc', 'dead')]
      expect(described_class.find_target(%w[orc kobold]).id).to eq('2')
      expect(described_class.find_target(['lesser orc'])).to be_nil
      expect(described_class.find_target(['troll'])).to be_nil
    end

    it 'passes over animated creatures and body parts, but for slush and the named kraken tentacles' do
      state[:npcs] = [npc.new('1', 'animated kobold', 'kobold'), npc.new('2', 'a kraken tentacle', 'tentacle')]
      expect(described_class.find_target(%w[kobold tentacle])).to be_nil
      state[:npcs] = [npc.new('3', 'animated slush', 'slush'), npc.new('4', 'a ghostly kraken tentacle', 'tentacle')]
      expect(described_class.find_target(['slush']).id).to eq('3')
      expect(described_class.find_target(['tentacle']).id).to eq('4')
    end

    it 'finds nothing in an empty room' do
      expect(described_class.find_target(['orc'])).to be_nil
    end
  end

  it 'targets a creature only when it is hostile' do
    orc = npc.new('2', 'a greater orc', 'orc')
    guard = npc.new('5', 'a town guard', 'guard')
    state[:targets] = [orc]
    expect(described_class.hostile?(orc)).to be(true)
    expect(described_class.target_npc!(orc)).to be(true)
    expect(described_class.target_npc!(guard)).to be(false)
    expect(log).to eq(['target #2'])
  end

  describe '.wander_standard!' do
    let(:room_type) { Struct.new(:id, :wayto, :timeto) }

    before { state[:room] = room_type.new(1, { '2' => 'north', '3' => 'east', '4' => 'west' }, {}) }

    it 'steps to a room not yet visited, then to the one visited longest ago, never across a boundary' do
      $wander_rooms = ['2']
      described_class.wander!(boundary: ['4'], delay: 1.0)
      described_class.wander!(boundary: ['4'], delay: 1.0)
      expect(log).to eq([[:move, 'east'], [:move, 'north']])
      expect($wander_rooms).to eq(%w[3 2])
    end

    it 'waits the delay when there is nowhere to go' do
      described_class.wander_standard!(boundary: %w[2 3 4], delay: 2.5)
      expect(log).to eq([[:sleep, 2.5]])
    end

    it 'does not step where a scripted time says there is no going, and calls a scripted way' do
      state[:room].timeto['2'] = proc {}
      state[:room].timeto['3'] = proc { 5 }
      state[:room].wayto['3'] = proc { log << :called }
      described_class.wander_standard!(boundary: ['4'], delay: 1.0)
      expect(log).to eq([:called])
    end
  end

  describe 'in the Elemental Confluence' do
    let(:room_type) { Struct.new(:id) }

    before { state[:title] = '[Elemental Confluence]' }

    it 'in GSIV learns where an exit leads, and notes the landmarks seen there' do
      state[:room] = room_type.new(23282)
      state[:exits] = %w[north east]
      state[:moves]['north'] = room_type.new(23283)
      state[:loot] = [Struct.new(:name).new('gaping bottomless pit')]
      described_class.wander!(boundary: [], delay: 1.0)
      expect($mapdb_confluence_wayto[23282]).to eq({ 'north' => 23283, 'east' => nil })
      expect($wander_rooms).to eq([23283])
      expect($mapdb_confluence_hot_pit).to eq(23283)
    end

    it 'forgets a landmark that is no longer where it was, hot side or cold' do
      $mapdb_confluence_cold_tranquility = 5
      $mapdb_confluence_hot_pit = 23283
      described_class.track_confluence_landmarks!(room_type.new(5))
      described_class.track_confluence_landmarks!(room_type.new(23283))
      expect([$mapdb_confluence_cold_tranquility, $mapdb_confluence_hot_pit]).to eq([nil, nil])
    end

    it 'in another game takes the next exit round the compass from the way it came in' do
      state[:game] = 'GSF'
      state[:exits] = %w[north south west]
      $mapdb_confluence_last_dir = 'north'
      described_class.wander!(boundary: [], delay: 1.0)
      expect(log).to eq([[:move, 'west']])
    end

    it 'in another game looks again when the exits were stale' do
      state[:game] = 'GSF'
      state[:exits] = %w[north]
      state[:moves]['north'] = false
      state[:look] = '<compass><dir value="e"/></compass>'
      described_class.wander!(boundary: [], delay: 1.0)
      expect(log).to eq([[:move, 'north'], [:move, 'e']])
    end
  end
end
