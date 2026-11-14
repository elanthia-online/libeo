# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/carry'
require_relative '../../scripts/eo/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/loot/context'
require_relative '../../scripts/eo/loot/pass'

RSpec.describe EO::Loot::Pass do
  let(:thing) { Struct.new(:id, :name, :type, :status, keyword_init: true) }
  let(:boar) { thing.new(id: '1', name: 'wild boar', type: '') }
  let(:wolf) { thing.new(id: '2', name: 'dire wolf', type: '') }
  let(:child) { thing.new(id: '3', name: 'wolf child', type: '') }
  let(:ruby) { thing.new(id: '10', name: 'blue ruby', type: 'gem') }
  let(:relic) { thing.new(id: '11', name: 'old relic', type: 'collectible') }
  let(:rock) { thing.new(id: '12', name: 'grey rock', type: 'junk') }
  let(:events) { [] }
  let(:settings) { { loot_stance: 'guarded', use_bloodbands: false, sigil_determination_on_fail: false } }
  let(:context) { EO::Loot::Context.new(settings: settings, say: ->(type:, text:) { events << [:say, type, text] }, critter_exclude_regex: /\bnever\b/) }
  let(:hands_now) { [thing.new(id: nil, name: 'Empty'), thing.new(id: nil, name: 'Empty')] }
  let(:hands) do
    log = events
    Class.new do
      define_method(:free_hand) { log << [:free_hand] }
      define_method(:free_hands) { |left: false| log << [:free_hands, left] }
      define_method(:single_drag) { |item| log << [:single_drag, item.name] }
    end.new
  end
  let(:candidates) { [] }
  let(:specials) { {} }
  let(:regular_steps) { [] }
  let(:regular_effect) { -> {} }
  let(:floor) do
    log = events
    objs = candidates
    handled = specials
    steps = regular_steps
    effect = regular_effect
    fake = Object.new
    fake.define_singleton_method(:room_candidates) { log << [:room_candidates]; objs }
    fake.define_singleton_method(:open_bags) { |list| log << [:open_bags, list.map(&:name)] }
    fake.define_singleton_method(:special) { |item| log << [:special, item.name]; handled.fetch(item.name, false) }
    fake.define_singleton_method(:room_regular_steps) do |list|
      log << [:regular_steps, list.map(&:name)]
      steps.map { |label| -> { log << [:regular, label]; effect.call } }
    end
    fake.define_singleton_method(:forget_weights) { log << [:forget_weights] }
    fake
  end
  let(:skin_steps) { [] }
  let(:skin_pass) do
    log = events
    queue = skin_steps
    fake = Object.new
    fake.define_singleton_method(:start) { log << [:skin_start] }
    fake.define_singleton_method(:step) { log << [:skin_step]; queue.shift || :done }
    fake.define_singleton_method(:finish) { log << [:skin_finish] }
    fake
  end
  let(:dead) { [boar, wolf] }
  let(:with_skin) { true }
  let(:with_floor) { true }
  let(:pass) do
    log = events
    corpses = dead
    skin = skin_pass
    described_class.new(
      context, floor: floor, hands: hands, corpses: -> { log << [:corpses]; corpses }, skin: (-> { log << [:skin_new]; skin } if with_skin),
               floor_loot: with_floor, stance: ->(name) { log << [:stance, name] }, coin_hand: -> { log << [:coin_hand] },
               return_hands: -> { log << [:return_hands] }
    )
  end

  before do
    stub_const('Spell', Class.new { define_singleton_method(:[]) { |_name| Struct.new(:active?).new(false) } })
    pair = hands_now
    stub_const('GameObj', Module.new do
      define_singleton_method(:right_hand) { pair[0] }
      define_singleton_method(:left_hand) { pair[1] }
    end)
    allow(EO::Loot).to receive(:search) { |corpse, **| events << [:search, corpse.name]; [:searched] }
    log = events
    pass.define_singleton_method(:sleep) { |seconds| log << [:sleep, seconds] }
    pass.define_singleton_method(:fput) { |command| log << [:fput, command] }
  end

  def kinds = events.reject { |e| e.first == :say && e[1] == 'debug' }

  describe '#run' do
    before do
      skin_steps.push(:skinned, :no_tool)
      candidates.push(ruby, relic, rock)
      specials['old relic'] = true
      regular_steps.push('a', 'b')
    end

    it 'skins, searches, loots the floor and gives the hands back, in that order' do
      pass.run
      expect(kinds.map(&:first)).to eq(
        %i[sleep stance skin_new skin_start skin_step skin_step skin_step skin_finish corpses stance search stance search stance
           room_candidates open_bags special special special regular_steps regular regular forget_weights coin_hand return_hands
           skin_finish forget_weights]
      )
    end

    it 'remembers what was in each hand and takes the loot stance before anything' do
      pair = hands_now
      pair[0] = thing.new(id: '90', name: 'rapier')
      pass.run
      expect(context.right_hand.name).to eq('rapier')
      expect(events.first(2)).to eq([[:sleep, 0.2], [:stance, 'guarded']])
    end

    it 'looks for the dead only when it needs them, after the skinning' do
      pass.run
      expect(events.index([:corpses])).to be > events.index([:skin_finish])
    end

    it 'leaves what was not handled to the ordinary loot, and nothing else' do
      pass.run
      expect(events).to include([:special, 'blue ruby'], [:special, 'old relic'], [:special, 'grey rock'],
                                [:regular_steps, ['blue ruby', 'grey rock']])
    end

    context 'without a skinning pass' do
      let(:with_skin) { false }

      it 'does not skin' do
        pass.run
        expect(events.map(&:first)).not_to include(:skin_new, :skin_start)
        expect(events.map(&:first)).to include(:search)
      end
    end
  end

  describe 'one step at a time' do
    it 'says what each step did' do
      skin_steps.push(:skinned)
      candidates.push(ruby, relic)
      specials['old relic'] = true
      regular_steps.push('a')
      pass.start
      results = []
      results << pass.step until results.last == :done
      expect(results).to eq(%i[skinned searched searched special looted done])
    end

    it 'names the corpse or the item a step handled' do
      candidates.push(relic)
      specials['old relic'] = true
      pass.start
      expect(pass.step).to eq(:skinned).or eq(:searched)
      pass.step until pass.last == boar
      expect(pass.last).to eq(boar)
      pass.step until pass.last == relic
      expect(pass.last).to eq(relic)
    end

    it 'starts by itself on the first step' do
      expect(pass.step).to eq(:searched)
      expect(events.first).to eq([:sleep, 0.2])
    end

    it 'says :done after it is done, without doing more' do
      pass.run
      events.clear
      expect(pass.step).to eq(:done)
      expect(events).to be_empty
    end
  end

  describe 'a character in a berserk' do
    before { stub_const('Spell', Class.new { define_singleton_method(:[]) { |_name| Struct.new(:active?).new(true) } }) }

    it 'says it cannot loot and does nothing' do
      pass.run
      expect(kinds).to eq([[:say, 'info', ' Berserk is active and preventing you from looting.'], [:forget_weights]])
    end

    it 'is done at the first step' do
      expect(pass.step).to eq(:done)
    end
  end

  describe 'searching' do
    it 'skips what is not worth searching, and the excluded' do
      allow(EO::Loot).to receive(:searchable?).and_call_original
      dead.replace([boar, child, thing.new(id: '4', name: 'never wolf', type: '')])
      with_skin_off = true
      pass.run
      expect(events.select { |e| e.first == :search }.map(&:last)).to eq(['wild boar'])
      expect(with_skin_off).to be(true)
    end

    it 'ends in the loot stance, though nothing was searched, when there were dead' do
      dead.replace([child])
      pass.run
      expect(events.select { |e| e.first == :stance }.size).to eq(2)
    end

    it 'does not change stance at the end when there were no dead' do
      dead.replace([])
      pass.run
      expect(events.select { |e| e.first == :stance }.size).to eq(1)
    end

    it 'raises a blood band at each corpse when the settings say so' do
      settings[:use_bloodbands] = true
      context.blood_band = thing.new(id: '77', name: 'band')
      dead.replace([boar])
      pass.run
      expect(events).to include([:fput, 'raise #77 at #1'])
    end

    it 'hands the search what frees a hand and what puts an item away' do
      allow(EO::Loot).to receive(:search) do |corpse, free:, stow:, **|
        free.call(:left)
        free.call(:right)
        stow.call(ruby)
        events << [:search, corpse.name]
        [:searched]
      end
      dead.replace([boar])
      pass.run
      expect(events).to include([:free_hands, true], [:free_hand], [:single_drag, 'blue ruby'])
    end
  end

  describe 'the floor' do
    context 'when told not to' do
      let(:with_floor) { false }

      it 'does not touch the floor, and still gives the hands back' do
        pass.run
        expect(events.map(&:first)).not_to include(:room_candidates)
        expect(events.map(&:first)).to include(:coin_hand, :return_hands)
      end
    end

    it 'goes straight on when the room holds no loot, forgetting the weights' do
      pass.run
      expect(events.map(&:first)).not_to include(:open_bags)
      expect(events.count { |e| e == [:forget_weights] }).to be >= 2
    end

    it 'does not ask for the ordinary loot when every item was handled as a special' do
      candidates.push(relic)
      specials['old relic'] = true
      pass.run
      expect(events.map(&:first)).not_to include(:regular_steps)
    end

    it 'opens the bags loot goes into once, before anything is looted' do
      candidates.push(ruby, relic)
      pass.run
      expect(events.count { |e| e.first == :open_bags }).to eq(1)
      expect(events.index([:open_bags, ['blue ruby', 'old relic']])).to be < events.index([:special, 'blue ruby'])
    end
  end

  describe 'something that could not be put away' do
    before do
      candidates.push(relic, ruby)
      specials['old relic'] = true
    end

    it 'says :no_room, naming the item, when a hand holds what it did not at the start' do
      pair = hands_now
      pass.start
      pass.step until pass.last == boar && false || events.include?([:special, 'old relic'])
      pair[1] = thing.new(id: '11', name: 'old relic', type: 'collectible')
      expect(pass.send(:stranded)).to eq(:no_room)
      expect(pass.last.name).to eq('old relic')
    end

    it 'says it from a search that left an item in the left hand' do
      pair = hands_now
      allow(EO::Loot).to receive(:search) do |_corpse, **|
        pair[1] = thing.new(id: '15', name: 'dropped dagger', type: 'weapon')
        [:searched]
      end
      pass.start
      expect(pass.step).to eq(:no_room)
      expect(pass.last.name).to eq('dropped dagger')
    end

    it 'says it from the ordinary loot that left an item in hand' do
      pair = hands_now
      candidates.push(rock)
      regular_steps.push('a')
      dead.replace([])
      pass.start
      allow(floor).to receive(:special).and_return(false)
      pair[0] = thing.new(id: '16', name: 'stuck gem', type: 'gem')
      results = []
      results << pass.step until %i[no_room done].include?(results.last)
      expect(results.last).to eq(:no_room)
      expect(pass.last.name).to eq('stuck gem')
    end

    it 'does not say it for what the left hand held at the start' do
      pair = hands_now
      pair[1] = thing.new(id: '91', name: 'shield')
      pass.start
      expect(pass.send(:stranded)).to be_nil
    end

    it 'does not say it for what was in the hands at the start' do
      pair = hands_now
      pair[0] = thing.new(id: '90', name: 'rapier')
      pass.start
      expect(pass.send(:stranded)).to be_nil
    end

    it 'says it from the step that left the item' do
      pass.start
      pair = hands_now
      allow(floor).to receive(:special) do |item|
        pair[0] = thing.new(id: item.id, name: item.name, type: item.type) if item.name == 'old relic'
        item.name == 'old relic'
      end
      results = []
      results << pass.step until %i[no_room done].include?(results.last)
      expect(results.last).to eq(:no_room)
      expect(pass.last.name).to eq('old relic')
    end
  end

  describe '#finish' do
    it 'ends the skinning and forgets the weights even when the pass was left half done' do
      skin_steps.push(:skinned, :skinned)
      pass.start
      pass.step
      events.clear
      pass.finish
      expect(events).to eq([[:skin_finish], [:forget_weights]])
    end

    it 'does nothing harmful before a start' do
      expect { pass.finish }.not_to raise_error
    end
  end

  describe '#restore_hands' do
    it 'gives each hand back what it held' do
      pass.restore_hands
      expect(events).to eq([[:return_hands]])
    end
  end
end
