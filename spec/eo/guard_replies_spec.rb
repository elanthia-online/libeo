# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/guild/npcs'
require_relative '../../scripts/eo/guild/taskmaster'
require_relative '../../scripts/eo/guild/guards'

# Replies copied from the game's own text (Kraken's Fall).
RESCUE = 'Luthrek says, "Ah, so you\'re from the Adventurer\'s Guild?  Yes, we do have a task for you.  One of our citizens is in quite ' \
         'the predicament.  Her young son ran away from home recently.  A local divinist has discerned glimpses of the child fleeing ' \
         'from a spectral triton protector in the Atoll near Kraken\'s Fall.  The child is still alive, though is in constant danger ' \
         'and is probably cowering wherever he can find somewhere to hide."'
HEIRLOOM = 'Luthrek says, "Ah, so you\'re from the Adventurer\'s Guild?  Yes, we do have a task for you.  One of our citizens was ' \
           'attacked by a triton warden in the Atoll near Kraken\'s Fall.  She barely escaped with her life.  Unfortunately, in her haste ' \
           'to escape, she dropped a family heirloom of great sentimental value to her.  She has put up a reward for its safe return.  ' \
           'The heirloom is a flowery enameled ring and you\'ll be able to identify it by the initials WE engraved upon it.  Hunt down ' \
           'the creature that attacked her, retrieve the heirloom, and report back to me."'

RSpec.describe EO::Guild::Tables do
  it 'knows a guard telling of a rescue and of a lost heirloom' do
    expect(RESCUE).to match(described_class::GUARD_RESPONSES)
    expect(HEIRLOOM).to match(described_class::GUARD_RESPONSES)
  end

  it 'does not take another taskmaster for a guard' do
    line = 'Delosa says, "Ah, so you\'re from the Adventurer\'s Guild?  Yes, we do have a task for you.  Bring me some skins."'
    expect(line).not_to match(described_class::GUARD_RESPONSES)
  end

  it 'does not take a line that only mentions the words' do
    expect('You think about how to retrieve the heirloom, and report back to me.').not_to match(described_class::GUARD_RESPONSES)
  end
end

RSpec.describe EO::Guild::Guards, '.ask' do
  let(:calls) { [] }

  def visit(reply)
    stub_const('Room', Class.new { def self.[](room) = Struct.new(:uid).new([room]) })
    allow(EO::Guild::NPCs).to receive(:guard_rooms).and_return([1, 2, 3])
    allow(EO).to receive(:go2) { |room| calls << [:go2, room] }
    allow(EO).to receive(:result) do |cmd, _|
      calls << [:ask, cmd]
      reply
    end
    allow(described_class).to receive_messages(guards_here: ['guard'], checkbounty: 'x', checkright: false)
    allow(described_class).to receive(:fput)
    allow(EO::Guild::Taskmaster).to receive(:changed?).and_return(false)
    described_class.ask(town: 'Kraken', bounty_text: 'x')
  end

  it 'goes on to the next guard room when a guard does not answer at all' do
    visit(nil)
    expect(calls.count { |c| c.first == :go2 }).to eq(3)
  end

  it 'goes on to the next guard room when a guard has nothing for us' do
    visit("I don't have any tasks for you right now.")
    expect(calls.count { |c| c.first == :go2 }).to eq(3)
  end

  it 'stops at a guard who tells of a rescue' do
    visit(RESCUE)
    expect(calls.count { |c| c.first == :go2 }).to eq(1)
  end
end
