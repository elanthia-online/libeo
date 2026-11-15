# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/guild/npcs'
require_relative '../../scripts/eo/guild/location'

# A map of rooms for the guild specs: Room.list, Room[id or "u<uid>"],
# Room.current, and Map.ids_from_uid.
RSpec.shared_context 'a guild map' do
  let(:room_type) do
    Struct.new(:id, :uid, :tags, :location, :wayto, :town, :reach, :nearest, keyword_init: true) do
      def find_nearest_by_tag(_tag) = town
      def path_to(room) = reach.nil? || reach.include?(room.id) ? [id, room.id] : nil
      def find_nearest(ids) = nearest || ids.first
    end
  end
  let(:rooms) { [] }
  let(:here) { [nil] }

  def room(id, **opts)
    made = room_type.new(id: id, uid: [id], tags: [], wayto: {}, **opts)
    rooms << made
    made
  end

  before do
    all = rooms
    current = here
    stub_const('Room', Class.new do
      define_singleton_method(:list) { all }
      define_singleton_method(:current) { current.first }
      define_singleton_method(:[]) do |key|
        next all.find { |r| r.uid.include?(key[1..].to_i) } if key.to_s.start_with?('u')

        all.find { |r| r.id == key.to_i }
      end
    end)
    stub_const('Map', Class.new { define_singleton_method(:ids_from_uid) { |uid| all.select { |r| r.uid.include?(uid) }.map(&:id) } })
  end
end

RSpec.describe EO::Guild::Tables do
  include_context 'a guild map'

  it 'names every kind of task the settings know' do
    expect(described_class::TASK_TYPES).to include(cull: 'culling', dangerous: 'boss_culling', herb: 'foraging', rescue_assignment: 'rescue')
    expect(described_class::TASK_TYPES.size).to eq(16)
  end

  it 'knows the people by the names the rooms give them' do
    expect('the furrier').to match(described_class::FURRIER_NAMES)
    expect('Zirconia').to match(described_class::JEWELER_NAMES)
    expect('old Mistress Lomara').to match(described_class::HERBALIST_NAMES)
  end

  it "has a room for every town, and Sailor's Grief by the game" do
    expect(described_class.town_uids('GSIV')).to include("Wehnimer's Landing" => 'u7120', 'Contempt' => 'u7150608')
    expect(described_class.town_uids('GSF')['Contempt']).to eq('u7150607')
    expect(described_class.town_uids('GSIV').size).to eq(13)
  end

  it "gives the herbalists' rooms the map has" do
    room(325, uid: [1015])
    expect(described_class.herbalist_rooms).to eq([325])
  end

  it 'tells a forage that hurt the hand from one that only failed' do
    hurt = 'As you forage around you suddenly feel a sharp pain in your right hand!'
    expect(hurt).to match(described_class::FORAGE_RESULT)
    expect(hurt).to match(described_class::FORAGE_INJURY)
    expect('You stumble about in a fruitless attempt at foraging.').not_to match(described_class::FORAGE_INJURY)
  end
end

RSpec.describe EO::Guild::NPCs do
  include_context 'a script lending helpers'
  include_context 'a guild map'

  let(:npcs) { [] }

  before do
    present = npcs
    stub_const('GameObj', Class.new do
      define_singleton_method(:npcs) { present }
      define_singleton_method(:room_desc) { [] }
    end)
    EO.use(script: 'spec', say: ->(type, text) { said << [type, text] })
    described_class.define_singleton_method(:echo) { |*_| nil }
  end

  after { described_class.singleton_class.remove_method(:echo) }

  describe '.find' do
    it 'finds someone by name at once' do
      npcs << Struct.new(:name).new('the furrier')
      expect(described_class.find(EO::Guild::Tables::FURRIER_NAMES).name).to eq('the furrier')
      expect(sent).to be_empty
    end

    it 'looks five times, waiting between and saying so from the second on' do
      expect(described_class.find(/furrier/i)).to be_nil
      expect(sent).to eq([:wait] * 5)
      expect(said.count { |type, _| type == 'yellow' }).to eq(4)
    end
  end

  describe '.taskmaster' do
    it 'walks to the guild and asks the Taskmaster' do
      here[0] = room(1)
      expect(described_class.taskmaster).to eq('Taskmaster')
      expect(went).to eq(['advguild'])
    end

    it 'stays put in a guild room, and asks Halfwhistle in the Hinterwilds' do
      here[0] = room(9, uid: [EO::Guild::Tables::HINTERWILDS_GUILD_UID], tags: ['advguild'])
      expect(described_class.taskmaster).to eq('Halfwhistle')
      expect(went).to be_empty
    end

    it "looks through Sailor's Grief three times for Seldit, then has no one" do
      here[0] = room(50, uid: [7_150_601])
      expect(described_class.taskmaster).to be_nil
      expect(went.size).to eq(3 * EO::Guild::Tables::SAILORS_GRIEF_UIDS.size)
      npcs << Struct.new(:name).new('First Mate Seldit')
      expect(described_class.taskmaster).to eq('Seldit')
    end
  end

  it "lists a town's guard rooms that can be walked to" do
    square = room(228, uid: [7120])
    room(10, tags: ['advguard'], town: 228)
    room(11, tags: ['advguard2'], town: 228)
    room(12, tags: ['advguard'], town: 999)
    room(13, tags: ['bank'], town: 228)
    square.reach = [10, 11, 12, 13]
    allow(Room).to receive(:[]).and_call_original
    allow(Room).to receive(:[]).with(228).and_return(square)
    expect(described_class.guard_rooms("Wehnimer's Landing", EO::Guild::Tables.town_uids('GSIV'))).to eq([10, 11])
    square.reach = [10]
    expect(described_class.guard_rooms("Wehnimer's Landing", EO::Guild::Tables.town_uids('GSIV'))).to eq([10])
  end
end

RSpec.describe EO::Guild::Location do
  include_context 'a script lending helpers'
  include_context 'a guild map'

  before { EO.use(script: 'spec', say: ->(type, text) { said << [type, text] }) }

  it 'reads a room id as written, or looks a uid up' do
    room(325, uid: [1015])
    expect(described_class.room_id('325')).to eq(325)
    expect(described_class.room_id('u1015')).to eq(325)
    expect(described_class.room_id('u999')).to be_nil
  end

  describe '.find' do
    before do
      here[0] = room(1, location: 'the town')
      room(2, location: "Whistler's Pass", wayto: { '3' => 'north', '1' => 'south' })
      room(3, location: "Whistler's Pass", wayto: { '2' => 'south', '4' => 'north', '5' => 'east' })
      room(4, location: 'the mountains')
      room(5, location: "Whistler's Pass", wayto: { '3' => 'west' })
    end

    it 'gives the nearest room of the place and the rooms just outside it' do
      expect(described_class.find("Whistler's Pass")).to eq(['2', '1,4'])
    end

    it 'leaves bad rooms out, which makes them boundaries' do
      expect(described_class.find("Whistler's Pass", bad_rooms: [5])).to eq(['2', '1,4,5'])
    end

    it 'has nothing for a place no room belongs to' do
      expect(described_class.find('the Moon')).to be_nil
    end
  end

  it 'cuts a place down to a connected part around the start' do
    room(1, wayto: { '2' => 'n', '9' => 'out' })
    room(2, wayto: { '1' => 's', '3' => 'n' })
    room(3, wayto: { '2' => 's' })
    room(7, wayto: {})
    expect(described_class.limit(1, [1, 2, 3, 7], 2)).to eq([1, 2])
    expect(described_class.limit(1, [1, 2, 3, 7])).to eq([1, 2, 3])
  end
end
