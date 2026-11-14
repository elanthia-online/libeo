# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/cleanse/tables'
require_relative '../../scripts/eo/cleanse/hazards'
require_relative '../../scripts/eo/cleanse/traps'

# The limits the cleanse code puts on what it tries again: swings at a
# runestone, searches and disarms of a trap, the wait for a rash to go.
RSpec.describe 'cleanse limits' do
  let(:thing) { Struct.new(:id, :name) }

  describe EO::Cleanse::Hazards, '.break_runestone' do
    let(:stone) { thing.new('77', 'onslaught runestone') }
    let(:swings) { [] }

    # answers: the lines of each swing in turn; loot: whether it is still there
    def break_with(answers, loot: true, targetable: true)
      allow(described_class).to receive(:target).and_return(targetable)
      allow(described_class).to receive(:waitrt?)
      stub_const('GameObj', Class.new { define_singleton_method(:loot) { loot ? [Struct.new(:id).new('77')] : [] } })
      queue = answers.dup
      log = swings
      util = Module.new
      util.define_singleton_method(:issue_command) do |cmd, *, **|
        log << cmd
        queue.shift || []
      end
      stub_const('Lich::Util', util)
      described_class.break_runestone(stone)
    end

    it 'gives up after five swings' do
      expect(break_with([])).to eq(:standing)
      expect(swings.size).to eq(5)
    end

    it 'stops at the swing that shatters it' do
      shatter = ['It crashes to the ground and shatters into pale dust.']
      expect(break_with([[], [], shatter, []])).to eq(:shattered)
      expect(swings.size).to eq(3)
    end

    it 'stops when it is no longer in the room' do
      expect(break_with([[]], loot: false)).to eq(:gone)
      expect(swings.size).to eq(1)
    end

    it 'does not swing at what cannot be targeted' do
      expect(break_with([], targetable: false)).to eq(:untargetable)
      expect(swings).to be_empty
    end
  end

  describe EO::Cleanse::Traps do
    let(:here) { Struct.new(:id).new(5) }

    before do
      stub_const('Room', Class.new.tap { |c| c.define_singleton_method(:current) { Struct.new(:id).new(5) } })
      allow(EO).to receive(:settle)
      allow(described_class).to receive_messages(dead?: false, muckled?: false)
    end

    # answers: the lines of each command in turn
    def run(method, answers, room: 5)
      queue = answers.dup
      sent = []
      allow(EO::Cleanse).to receive(:command) do |cmd, *|
        sent << cmd
        queue.shift || ['d100: 12 vs 60']
      end
      [described_class.public_send(method, room), sent]
    end

    describe '.search' do
      it 'tries three times and no more' do
        outcome, sent = run(:search, [])
        expect(outcome).to eq(:exhausted)
        expect(sent.size).to eq(3)
      end

      it 'stops at what it finds, what is not there, and what it cannot see' do
        expect(run(:search, [['Success!']]).first).to eq(:found)
        expect(run(:search, [["You don't find anything of interest here."]]).first).to eq(:clear)
        expect(run(:search, [["You can't see well enough to search around."]]).first).to eq(:blind)
      end

      it 'does not search in another room' do
        outcome, sent = run(:search, [], room: 9)
        expect(outcome).to eq(:moved)
        expect(sent).to be_empty
      end

      it 'gives up once its twenty seconds are used' do
        now = Time.now
        allow(Time).to receive(:now).and_return(now, now + 21)
        outcome, sent = run(:search, [])
        expect(outcome).to eq(:timeout)
        expect(sent).to be_empty
      end
    end

    describe '.disarm' do
      it 'tries three times and then leaves it armed' do
        outcome, sent = run(:disarm, [])
        expect(outcome).to eq(:armed)
        expect(sent.size).to eq(3)
      end

      it 'is disarmed on the first success' do
        outcome, sent = run(:disarm, [['d100: 80 vs 60 Success!']])
        expect(outcome).to eq(:disarmed)
        expect(sent.size).to eq(1)
      end
    end

    describe '.wait_out_rash' do
      let(:seconds) { [] }

      before do
        allow(described_class).to receive(:empty_hands)
        allow(described_class).to receive(:fill_hands)
        allow(described_class).to receive(:sleep) { |n| seconds << n }
      end

      it 'is over when the rash goes' do
        calls = 0
        allow(described_class).to receive(:reget) do |*|
          calls += 1
          calls == 3 ? ['You no longer feel so defenseless and the rash seems to disappear.'] : []
        end
        expect(described_class.wait_out_rash).to eq(:gone)
        expect(seconds.size).to eq(2)
      end

      it 'gives up after three minutes' do
        now = Time.now
        clock = [now, now + 10, now + 100, now + 181]
        allow(Time).to receive(:now) { clock.size > 1 ? clock.shift : clock.first }
        calls = 0
        allow(described_class).to receive(:reget) { (calls += 1) > 50 ? raise('waited without end') : [] }
        expect(described_class.wait_out_rash).to eq(:still_itchy)
        expect(seconds.size).to eq(2)
      end
    end
  end
end
