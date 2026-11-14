# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/wander'

RSpec.describe EO::Wander do
  let(:npc) { Struct.new(:id, :name, :noun, :status, keyword_init: true) }

  def room_with(*npcs, targets: npcs)
    stub_const('GameObj', Class.new do
      define_singleton_method(:npcs) { npcs }
      define_singleton_method(:targets) { targets }
    end)
  end

  it 'picks the first named creature in priority order, skipping pets, limbs and the dead' do
    kobold = npc.new(id: '1', name: 'a kobold', noun: 'kobold', status: '')
    troll = npc.new(id: '2', name: 'a troll', noun: 'troll', status: '')
    room_with(npc.new(id: '3', name: 'animated skeleton', noun: 'skeleton', status: ''),
              npc.new(id: '4', name: 'a kraken arm', noun: 'arm', status: ''),
              npc.new(id: '5', name: 'a dead troll', noun: 'troll', status: 'dead'), kobold, troll)
    expect(described_class.find(%w[troll kobold])).to eq(troll)
    expect(described_class.find(%w[skeleton arm])).to be_nil
    expect(described_class.find(%w[nothing])).to be_nil
  end

  it 'keeps animated slush and a named kraken tentacle' do
    slush = npc.new(id: '6', name: 'animated slush', noun: 'slush', status: '')
    tentacle = npc.new(id: '7', name: 'an ancient kraken tentacle', noun: 'tentacle', status: '')
    room_with(slush, tentacle)
    expect(described_class.find(['slush'])).to eq(slush)
    expect(described_class.find(['tentacle'])).to eq(tentacle)
  end

  it 'tells hostile creatures from town folk' do
    guard = npc.new(id: '8', name: 'a town guard', noun: 'guard', status: '')
    orc = npc.new(id: '9', name: 'an orc', noun: 'orc', status: '')
    room_with(guard, orc, targets: [orc])
    expect(described_class.hostile?(orc)).to be(true)
    expect(described_class.hostile?(guard)).to be(false)
  end

  describe 'Confluence' do
    it 'moves a landmark here, clears it when gone, and leaves it otherwise' do
      c = described_class::Confluence
      expect(c.landmark(nil, 5, true)).to eq(5)
      expect(c.landmark(5, 5, false)).to be_nil
      expect(c.landmark(7, 5, false)).to eq(7)
    end

    context 'when the exits it read are stale' do
      let(:confluence) { described_class::Confluence }
      let(:moves) { [] }

      before do
        stub_const('XMLData', Class.new { def self.room_exits = ['north'] })
        here = Struct.new(:id).new(23_282)
        stub_const('Room', Class.new { define_singleton_method(:current) { here } })
        sent = moves
        confluence.define_singleton_method(:move) { |way| (sent << way) && false }
        %i[status_tags waitrt?].each { |m| confluence.define_singleton_method(m) { nil } }
        $mapdb_confluence_wayto = nil
        $mapdb_confluence_last_dir = nil
      end

      after do
        %i[move status_tags waitrt?].each { |m| confluence.singleton_class.remove_method(m) }
        $mapdb_confluence_wayto = $mapdb_confluence_last_dir = nil
      end

      it 'takes an exit LOOK shows' do
        allow(confluence).to receive(:dothistimeout).and_return('<compass><dir value="e"/></compass>')
        confluence.mapped_step([])
        confluence.turning_step
        expect(moves).to eq(%w[north e north e])
      end

      it 'does not move when LOOK is not answered or shows none' do
        allow(confluence).to receive(:dothistimeout).and_return(nil, '<compass></compass>')
        confluence.mapped_step([])
        confluence.turning_step
        expect(moves).to eq(%w[north north])
      end

      it 'starts a step over ten times at most' do
        tries = 0
        allow(confluence).to receive(:move) { (tries += 1) && raise('the room shifted') }
        expect { confluence.mapped_step([]) }.not_to raise_error
        expect(tries).to eq(confluence::RESTARTS + 1)
      end
    end
  end
end
