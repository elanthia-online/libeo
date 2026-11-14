# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/town'

RSpec.describe EO::Town do
  include_context 'a script lending helpers'

  let(:room_type) do
    Struct.new(:id, :location, :uid, :tags, :nearest, :paths, keyword_init: true) do
      def find_nearest_by_tag(tag) = nearest[tag]
      def path_to(room) = paths[room.id]
    end
  end
  let(:rooms) { {} }
  let(:here) { room(1, 'the town of Wehnimer\'s Landing') }

  def room(id, location = nil, uid: [id], tags: [], nearest: {}, paths: {})
    rooms[id] = room_type.new(id: id, location: location, uid: uid, tags: tags, nearest: nearest, paths: paths)
  end

  before do
    all = rooms
    current = here
    stub_const('Room', Class.new do
      define_singleton_method(:current) { current }
      define_singleton_method(:[]) { |id| all[id] }
    end)
    allow(described_class).to receive(:sleep)
  end

  it 'knows Four Winds Isle by its three locations' do
    expect(described_class.fwi?(room(2, 'Mist Harbor'))).to be(true)
    expect(described_class.fwi?(room(3, 'the Isle of Four Winds'))).to be(true)
    expect(described_class.fwi?(here)).to be(false)
  end

  describe '.nearest_shop' do
    before do
      here.nearest.merge!('town' => 10, 'pawnshop' => 44, 'gemshop' => 45)
      room(10, 'the Hinterwilds', uid: [described_class::HINTERWILDS_TOWN_UID])
    end

    it 'skips the shops the Hinterwilds town does not have' do
      expect(described_class.nearest_shop('pawnshop')).to be_nil
      expect(described_class.nearest_shop('gemshop')).to eq(45)
    end

    it 'goes anyway for a character who travels to sell' do
      expect(described_class.nearest_shop('pawnshop', travels: true)).to eq(44)
    end

    it 'goes when the town is another, or not known' do
      rooms[10].uid = [228]
      expect(described_class.nearest_shop('pawnshop')).to eq(44)
      here.nearest.delete('town')
      expect(described_class.nearest_shop('pawnshop')).to eq(44)
    end
  end

  describe '.in_region' do
    let(:towns) { [room(20, "the town of Wehnimer's Landing", nearest: { 'furrier' => 21 }), room(30, 'the Hinterwilds', nearest: { 'furrier' => 31 })] }
    let(:ferry) { 99 }

    before do
      room(21)
      room(31)
      edge = ferry
      stub_const('Map', Class.new { define_singleton_method(:ids_from_uid) { |uid| uid == 14_001_002 ? [edge] : [] } })
    end

    it "finds the shop in the bounty's town when the path stays in the region" do
      here.paths[21] = [1, 5, 21]
      expect(described_class.in_region('furrier', town: "Wehnimer's Landing", towns: towns)).to eq(21)
    end

    it 'has none when the path crosses a ferry, a cart or a portmaster' do
      here.paths[21] = [1, ferry, 21]
      expect(described_class.in_region('furrier', town: "Wehnimer's Landing", towns: towns)).to be_nil
    end

    it 'reads Cold River as the Hinterwilds, and has none for a town it does not know' do
      here.paths[31] = [1, 31]
      expect(described_class.in_region('furrier', town: 'Cold River', towns: towns)).to eq(31)
      expect(described_class.in_region('furrier', town: 'Zul Logoth', towns: towns)).to be_nil
    end
  end

  describe '.leave_fwi' do
    let(:fputs) { [] }

    before do
      log = fputs
      described_class.define_singleton_method(:fput) { |cmd| log << cmd }
      stub_const('GameObj', Class.new { define_singleton_method(:[]) { |_name| nil } })
    end

    after { described_class.singleton_class.remove_method(:fput) }

    it 'does nothing off the isle, or on it with no trinket named' do
      expect(described_class.leave_fwi(trinket: 'pendant', return_room: nil)).to eq(:elsewhere)
      here.nearest['town'] = described_class::FWI_TOWN
      expect(described_class.leave_fwi(trinket: nil, return_room: 228)).to eq(:no_trinket)
      expect(went).to be_empty
    end

    it 'walks to the dock and on to the return room' do
      here.nearest['town'] = described_class::FWI_TOWN
      expect(described_class.leave_fwi(trinket: 'pendant', return_room: 228)).to eq(:left)
      expect(went).to eq([described_class::FWI_DOCK, 228])
      expect(fputs).to be_empty
    end

    it 'turns a worn trinket where it is when no return room is set' do
      here.nearest['town'] = described_class::FWI_TOWN
      stub_const('GameObj', Class.new { define_singleton_method(:[]) { |_name| Struct.new(:id).new('55') } })
      described_class.leave_fwi(trinket: 'pendant', return_room: nil)
      expect(fputs).to eq(['turn #55'])
    end
  end

  describe '.trash_can' do
    before { stub_const('GameObj', Struct.new(:id, :noun, :name)) }

    it 'reads the receptacle TRASH names' do
      answers['trash'] = ['You could discard items in a <a exist="-123" noun="barrel">large barrel</a>.']
      expect(described_class.trash_can.to_a).to eq(['-123', 'barrel', 'large barrel'])
    end

    it 'has none where the game says so' do
      answers['trash'] = ['You do not notice a trash receptacle here.']
      expect(described_class.trash_can).to be_nil
    end

    it 'has none when TRASH names none either way' do
      answers['trash'] = ['You could discard items somewhere.']
      expect(described_class.trash_can).to be_nil
    end
  end

  describe '.pool_worker' do
    let(:npcs) { [] }

    before do
      list = npcs
      stub_const('GameObj', Class.new { define_singleton_method(:npcs) { list } })
    end

    it 'finds the worker by the usual names without looking' do
      npcs << Struct.new(:name).new('scruffy dwarf')
      worker, lines = described_class.pool_worker
      expect(worker.name).to eq('scruffy dwarf')
      expect(lines).to be_nil
      expect(sent).to be_empty
    end

    it "goes by the room's own name for the worker when it has one" do
      here.tags << 'meta:boxpool:npc:Gertie'
      npcs.push(Struct.new(:name).new('scruffy dwarf'), Struct.new(:name).new('Gertie'))
      expect(described_class.pool_worker.first.name).to eq('Gertie')
    end

    it 'looks twenty times before giving up, and hands back the last look' do
      answers['look'] = ['<resource picture="0"/>']
      worker, lines = described_class.pool_worker
      expect(worker).to be_nil
      expect(lines).to eq(['<resource picture="0"/>'])
      expect(sent).to eq(['look'] * 20)
    end
  end
end
