# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/guild/disablers'

RSpec.describe EO::Guild::Disablers, '.target!' do
  let(:thing) { Struct.new(:name) }
  let(:skald) { thing.new('gigas skald') }
  let(:policy) { described_class::Policy.new(untargetable: ['old name']) }
  let(:calls) { [] }

  # answer: what the game says to TARGET RANDOM, nil for nothing; after: the
  # hostile creatures in the room when the answer came
  def target_with(answer, before: [skald], after: before)
    log = calls
    rooms = [before, after]
    stub_const('GameObj', Class.new { define_singleton_method(:targets) { rooms.size > 1 ? rooms.shift : rooms.first } })
    allow(described_class).to receive(:clear) { log << :clear }
    allow(described_class).to receive(:dothistimeout) do |cmd, seconds, _re|
      log << [cmd, seconds]
      answer
    end
    described_class.target!(policy)
  end

  it 'is true when the game says it is targeting something' do
    expect(target_with('You are now targeting a gigas skald.')).to be(true)
    expect(policy.untargetable).to eq(['old name'])
  end

  it 'clears stale lines first and waits five seconds, not for ever' do
    target_with('You are now targeting a gigas skald.')
    expect(calls).to eq([:clear, ['target random', 5]])
  end

  it 'learns the hostile names the game refuses, and only those' do
    expect(target_with('Could not find a valid target.')).to be(false)
    expect(policy.untargetable).to eq(['old name', 'gigas skald'])
  end

  it 'does not learn a name twice' do
    2.times { target_with('Could not find a valid target.') }
    expect(policy.untargetable).to eq(['old name', 'gigas skald'])
  end

  it 'learns nothing when the room changed while it waited' do
    target_with('Could not find a valid target.', after: [thing.new('rat')])
    expect(policy.untargetable).to eq(['old name'])
  end

  it 'gives up without learning anything when the game does not answer' do
    expect(target_with(nil)).to be(false)
    expect(policy.untargetable).to eq(['old name'])
  end

  it 'does not take the loot wording for the refusal' do
    expect(target_with('Could not find a valid target to loot.')).to be(false)
    expect(policy.untargetable).to eq(['old name'])
  end
end
