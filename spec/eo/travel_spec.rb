# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/travel'

RSpec.describe 'EO.room_id' do
  before do
    map = Class.new do
      def self.ids_from_uid(uid) = uid == 7120 ? [228] : []
    end
    stub_const('Map', map)
  end

  it 'passes a room id through, as a number or a string' do
    expect(EO.room_id(228)).to eq(228)
    expect(EO.room_id('228')).to eq(228)
    expect(EO.room_id(' 228 ')).to eq(228)
  end

  it 'resolves a uid through the map database' do
    expect(EO.room_id('u7120')).to eq(228)
    expect(EO.room_id('U7120')).to eq(228)
  end

  it 'raises for a uid the map does not know, instead of exiting the script' do
    expect { EO.room_id('u1') }.to raise_error(EO::UnknownRoom, /u1 is not in the map database/)
  end
end

RSpec.describe 'EO.at?' do
  include_context 'a fake map'

  let(:rooms) { [EOSpec::FakeRoom.new(id: 228, uid: [7120], tags: %w[town advguild])] }

  it 'matches by id, by uid, or by tag' do
    expect(EO.at?(228)).to be(true)
    expect(EO.at?('228')).to be(true)
    expect(EO.at?('u7120')).to be(true)
    expect(EO.at?('advguild')).to be(true)
    expect(EO.at?(229)).to be(false)
    expect(EO.at?('bank')).to be(false)
  end
end

RSpec.describe 'EO.go2' do
  let(:here) { { id: 1 } }
  let(:runs) { [] }

  before do
    room = here
    stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:id, :uid, :tags).new(room[:id], [], []) } })
    %i[hidden? invisible?].each { |m| EO.define_singleton_method(m) { false } }
    EO.define_singleton_method(:sleep) { |*| nil }
  end

  after { %i[hidden? invisible? sleep].each { |m| EO.singleton_class.remove_method(m) } }

  def script(running:, arrive_on:)
    room = here
    log = runs
    stub_const('Script', Class.new do
      define_singleton_method(:running?) { |_| running.shift || false }
      define_singleton_method(:run) do |*args|
        log << args.first
        room[:id] = 2 if log.size >= arrive_on
      end
    end)
  end

  it "waits out another script's walk, then walks" do
    script(running: [true, true, false], arrive_on: 1)
    expect(EO.go2(2)).to be(true)
    expect(runs).to eq(['go2'])
  end

  it 'does not wait for a go2 the caller has paused when forced' do
    script(running: [true] * 500, arrive_on: 1)
    allow(Time).to receive(:now).and_raise('waited')
    expect(EO.go2(2, force: true)).to be(true)
    expect(runs).to eq(['go2'])
  end

  it 'tries again when a walk does not arrive, and says so after three' do
    script(running: [], arrive_on: 2)
    expect(EO.go2(2)).to be(true)
    expect(runs.size).to eq(2)

    here[:id] = 1
    runs.clear
    script(running: [], arrive_on: 99)
    expect(EO.go2(2)).to be(false)
    expect(runs.size).to eq(3)
  end
end

RSpec.describe 'EO.wander' do
  # Lich's map holds a scripted edge as a StringProc: callable, but not a
  # Proc to is_a? or to case/when.
  let(:edge) { Class.new { define_method(:call) { nil } }.new }

  it 'leaves out an exit whose time is a scripted edge answering nil' do
    moved = []
    room = Struct.new(:wayto, :timeto).new({ '2' => 'north', '3' => 'east' }, { '2' => edge, '3' => 0.2 })
    stub_const('Room', Class.new { define_singleton_method(:current) { nil } })
    allow(Room).to receive(:current).and_return(room)
    EO.define_singleton_method(:move) { |way| moved << way }

    10.times { EO.wander([]) }
    expect(moved.uniq).to eq(['east'])
  ensure
    EO.singleton_class.remove_method(:move)
  end
end
