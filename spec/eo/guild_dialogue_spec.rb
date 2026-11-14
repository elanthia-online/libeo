# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/guild/npcs'
require_relative '../../scripts/eo/guild/taskmaster'
require_relative '../../scripts/eo/guild/assignments'
require_relative '../../scripts/eo/guild/vetting'

RSpec.describe EO::Guild::Taskmaster do
  include_context 'a script lending helpers'

  let(:state) { { type: :none, bounty: 'none' } }
  let(:asked) { [] }
  let(:replies) { [] }
  let(:after_ask) { [nil] }

  before do
    now = state
    log = asked
    queue = replies
    hook = after_ask
    stub_const('Bounty', Class.new { define_singleton_method(:type) { now[:type] } })
    EO.use(script: 'spec', say: ->(type, text) { said << [type, text] })
    allow(EO::Guild::NPCs).to receive(:taskmaster).and_return('Taskmaster')
    described_class.define_singleton_method(:checkbounty) { now[:bounty] }
    described_class.define_singleton_method(:fput) do |cmd|
      log << cmd
      hook.first&.call
      queue.shift
    end
    allow(described_class).to receive(:sleep)
  end

  after { %i[checkbounty fput].each { |m| described_class.singleton_class.remove_method(m) } }

  def given = state.merge!(type: :cull, bounty: 'tasked')

  it 'asks for a task until one is held' do
    after_ask[0] = -> { given }
    expect(described_class.ask('get')).to eq(:done)
    expect(asked).to eq(['ask Taskmaster about bounty '])
  end

  it 'asks for the kind a boost wants' do
    after_ask[0] = -> { given }
    described_class.ask('get', boost_type: 'culling')
    expect(asked).to eq(['ask Taskmaster about bounty culling'])
  end

  it 'asks twice in a round for a removal' do
    given
    after_ask[0] = -> { state.merge!(type: :none, bounty: 'none') if asked.size == 2 }
    expect(described_class.ask('remove')).to eq(:done)
    expect(asked).to eq(['ask Taskmaster about removal'] * 2)
  end

  it 'asks again, without counting it, when nobody was there to hear' do
    given
    replies.push('Who are you trying to ask?', nil, nil)
    after_ask[0] = -> { state.merge!(type: :none, bounty: 'none') if asked.size == 3 }
    expect(described_class.ask('remove')).to eq(:done)
    expect(asked.size).to eq(3)
    expect(EO::Guild::NPCs).to have_received(:taskmaster).twice
  end

  it 'counts the ask after three that nobody heard, so a round ends' do
    allow(described_class).to receive(:changed?).and_return(false)
    replies.concat(['Who are you trying to ask?'] * 50)
    expect(described_class.ask('get')).to eq(:gave_up)
    expect(asked.size).to eq(5 * 4)
  end

  it 'stops when a task is already held, or an expedite brings a new offer' do
    replies.push('You have already been assigned a task, Nisugi.', "I'm ready to assign you a new task.")
    expect(described_class.ask('get')).to eq(:already_assigned)
    expect(described_class.ask('expedite')).to eq(:ready)
  end

  it 'has no one to ask when the taskmaster cannot be found' do
    allow(EO::Guild::NPCs).to receive(:taskmaster).and_return(nil)
    expect(described_class.ask('get')).to eq(:no_taskmaster)
    expect(asked).to be_empty
  end

  it 'tries five rounds when nothing changes, saying so four times, then gives up' do
    allow(described_class).to receive(:changed?).and_return(false)
    expect(described_class.ask('get')).to eq(:gave_up)
    expect(asked.size).to eq(5)
    expect(said.size).to eq(4)
  end

  it 'reads boosts and vouchers from what the game lists' do
    answers['boost info'] = ["<d cmd='boost bounty'>Bounty Boosts</d>:   3"]
    answers['bounty'] = ['You have 0 expedited task reassignment vouchers remaining.']
    expect(described_class.boosts?).to be(true)
    expect(described_class.vouchers?).to be(false)
  end
end

RSpec.describe EO::Guild::Assignments do
  include_context 'a script lending helpers'

  let(:state) { { bounty: 'assignment' } }
  let(:fputs) { [] }
  let(:town) { Struct.new(:shop) { def find_nearest_by_tag(_tag) = shop }.new(44) }

  before do
    now = state
    log = fputs
    EO.use(script: 'spec', say: ->(type, text) { said << [type, text] })
    described_class.define_singleton_method(:checkbounty) { now[:bounty] }
    described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    allow(EO::Guild::NPCs).to receive(:find).and_return(Struct.new(:id).new('9'))
  end

  after { %i[checkbounty fput].each { |m| described_class.singleton_class.remove_method(m) } }

  it 'walks to the shop and asks by id until the task changes' do
    allow(EO::Guild::Taskmaster).to receive(:changed?).and_return(true)
    expect(described_class.ask('furrier', town)).to eq(:done)
    expect(went).to eq([44])
    expect(fputs).to eq(['ask #9 about bounty'])
  end

  it 'asks five times when nothing changes, then gives up' do
    allow(EO::Guild::Taskmaster).to receive(:changed?).and_return(false)
    expect(described_class.ask('jeweler', town)).to eq(:gave_up)
    expect(fputs.size).to eq(5)
  end

  it 'has no one to ask when the shopkeeper is not found' do
    allow(EO::Guild::NPCs).to receive(:find).and_return(nil)
    expect(described_class.ask('furrier', town)).to eq(:no_npc)
    expect(EO::Guild::NPCs).to have_received(:find).once
  end

  describe '.ask_guards' do
    let(:npcs) { [Struct.new(:name) { def to_s = name }.new('guard')] }
    let(:room_type) { Struct.new(:id, :uid, :location) }

    before do
      present = npcs
      rooms = { 10 => room_type.new(10, [10], 'the town'), 11 => room_type.new(11, [11], 'the town') }
      stub_const('GameObj', Class.new do
        define_singleton_method(:npcs) { present }
        define_singleton_method(:room_desc) { [] }
      end)
      stub_const('Room', Class.new do
        define_singleton_method(:[]) { |id| rooms[id] }
        define_singleton_method(:current) { rooms[10] }
      end)
      described_class.define_singleton_method(:checkright) { false }
      allow(EO::Guild::Taskmaster).to receive(:changed?).and_return(true)
    end

    after { described_class.singleton_class.remove_method(:checkright) }

    def visit = described_class.ask_guards([10, 11], containers: [], open: ->(_c) {}, missing: -> {})

    it 'stops at the first guard with something to say' do
      answers['ask guard about bounty'] = ['Ah, so you have returned.']
      expect(visit).to be(true)
      expect(went).to eq([10])
    end

    it 'gives a guard two seconds to show in his room' do
      shown = npcs.dup
      npcs.clear
      looks = 0
      allow(described_class).to receive(:sleep) { npcs.replace(shown) if (looks += 1) == 3 }
      answers['ask guard about bounty'] = ['Ah, so you have returned.']
      expect(visit).to be(true)
      expect(went).to eq([10])
      expect(looks).to eq(3)
    end

    it 'moves on from a room no guard shows in, after eight looks' do
      npcs.clear
      allow(described_class).to receive(:sleep)
      visit
      expect(went).to eq([10, 11])
      expect(described_class).to have_received(:sleep).with(0.25).exactly(14).times
    end

    it 'goes on to the next room when the guard has nothing' do
      answers['ask guard about bounty'] = ["I don't have any tasks for you right now."]
      visit
      expect(went).to eq([10, 11])
    end

    it 'takes a found heirloom out first, or asks what to do when it is missing' do
      state[:bounty] = 'You have located a silver ring and should bring it back to the guard.'
      ring = Struct.new(:id, :name).new('5', 'silver ring')
      bag = Struct.new(:contents).new([ring])
      described_class.define_singleton_method(:empty_hands) { nil }
      described_class.define_singleton_method(:fill_hands) { nil }
      answers['ask guard about bounty'] = ['You have completed your task.']
      described_class.ask_guards([10], containers: [bag], open: ->(_c) {}, missing: -> {})
      expect(sent.first).to eq('_drag #5 right')
      expect(described_class.ask_guards([10], containers: [], open: ->(_c) {}, missing: -> { :stop })).to be(false)
    ensure
      %i[empty_hands fill_hands].each { |m| described_class.singleton_class.remove_method(m) }
    end
  end
end

RSpec.describe EO::Guild::Vetting do
  let(:task_type) { Struct.new(:requirements, :creature, :herb, :gem, :area, :action, keyword_init: true) }
  let(:none) { { creature: [], herb: [], gem: [], location: [] } }

  def task(**req) = task_type.new(requirements: req, creature: req[:creature], herb: req[:herb], gem: req[:gem], area: req[:area], action: req[:action])

  it 'hands back a task whose creature, herb, gem or place is excluded, and says which' do
    reject, said = described_class.reject?(:cull, task(creature: 'Kobold'), exclude: none.merge(creature: ['KOBOLD']), wanted: %w[culling])
    expect(reject).to be(true)
    expect(said).to eq('Kobold is in the excluded list. Turning in bounty!')
    expect(described_class.reject?(:herb, task(herb: 'acantha leaf'), exclude: none.merge(herb: ['acantha']), wanted: %w[foraging]).first).to be(true)
  end

  it 'hands back a kind of task not taken, without a word' do
    expect(described_class.reject?(:skin, task, exclude: none, wanted: %w[culling])).to eq([true, nil])
    expect(described_class.reject?(:cull, task, exclude: none, wanted: %w[culling])).to eq([false, nil])
    expect(described_class.reject?(:creature_assignment, task, exclude: none, wanted: %w[skinning])).to eq([true, nil])
    expect(described_class.reject?(:creature_assignment, task, exclude: none, wanted: %w[boss_culling])).to eq([false, nil])
  end

  it 'tells the two kinds of heirloom task apart by what is to be done' do
    wanted = %w[heirloom_loot]
    expect(described_class.reject?(:heirloom, task(action: 'search'), exclude: none, wanted: wanted).first).to be(true)
    expect(described_class.reject?(:heirloom, task(action: 'loot'), exclude: none, wanted: wanted).first).to be(false)
  end

  it 'lower-cases an exclusion list where it stands' do
    list = ['KOBOLD']
    described_class.reject?(:cull, task(creature: 'troll'), exclude: none.merge(creature: list), wanted: %w[culling])
    expect(list).to eq(['kobold'])
  end
end
