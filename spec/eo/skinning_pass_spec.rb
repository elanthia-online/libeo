# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/carry'
require_relative '../../scripts/eo/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/loot/context'
require_relative '../../scripts/eo/skinning'
require_relative '../../scripts/eo/skinning/pass'

RSpec.describe EO::Skinning::Pass do
  let(:thing) { Struct.new(:id, :name, :type, keyword_init: true) }
  let(:boar) { thing.new(id: '1', name: 'wild boar', type: '') }
  let(:wolf) { thing.new(id: '2', name: 'dire wolf', type: '') }
  let(:krynch) { thing.new(id: '3', name: 'krynch', type: '') }
  let(:ghost) { thing.new(id: '4', name: 'ghostly warrior', type: '') }
  let(:knife) { thing.new(id: '10', name: 'skinning knife') }
  let(:club) { thing.new(id: '11', name: 'bone club') }
  let(:sheath) { thing.new(id: '12', name: 'baldric') }
  let(:sack) { thing.new(id: '13', name: 'leather sack') }
  let(:said) { [] }
  let(:saved) { [] }
  let(:settings) { { unskinnable: [], skin_kneel: true, skin_resolve: false, skin_604: false } }
  let(:ready) { { skin_weapon: knife, skin_weapon_blunt: club, skin_sheath: sheath, skin_sheath_blunt: sheath } }
  let(:held) { [] }
  let(:calls) { [] }
  let(:ensured) { [] }
  let(:context) do
    said_to = said
    saved_to = saved
    EO::Loot::Context.new(settings: settings, weapon_inv: [:inventory],
                          say: ->(type:, text:) { said_to << [type, text] }, save: -> { saved_to << true })
  end
  let(:hands) do
    log = calls
    in_hand = held
    Class.new do
      define_method(:free_hand) { log << :free_hand }
      define_method(:free_hands) { |both: false| log << (both ? :free_both : :free_hands) }
      define_method(:drag) { |tool| log << [:drag, tool.name]; in_hand << tool.id }
      define_method(:store_item) do |bag, tool, loose = false|
        log << [:store, bag.name, tool.name, loose]
        in_hand.delete(tool.id) unless bag.name == 'full sheath'
      end
    end.new
  end
  let(:ensure_items) { ->(**args) { ensured << args.slice(:key, :inventory, :check_hidden) } }

  def pass(corpses)
    described_class.new(context, corpses: corpses, hands: hands, ensure_items: ensure_items)
  end

  before do
    ready_list = ready
    stub_const('ReadyList', Module.new { define_singleton_method(:ready_list) { ready_list } })
    stub_const('StowList', Module.new { define_singleton_method(:stow_list) { { default: Struct.new(:name).new('leather sack') } } })
    stub_const('Bounty', Module.new)
    stub_const('GameObj', Module.new { define_singleton_method(:left_hand) { Struct.new(:id).new('99') } })
    in_hand = held
    allow(EO::Hands).to receive(:holding?) { |tool| in_hand.include?(tool.id) }
    allow(EO::Skinning).to receive(:occasional?).and_return(false)
    allow(EO::Skinning).to receive(:prepare)
    allow(EO::Skinning).to receive(:stand_up)
    allow(EO::Skinning).to receive(:skin).and_return([])
    EO::Skinning.define_singleton_method(:waitrt?) { nil }
  end

  after { EO::Skinning.singleton_class.remove_method(:waitrt?) }

  it 'skins the edged group, then the blunt one, with each its own tool, and stands up once' do
    result = pass([boar, krynch, wolf]).run

    expect(result).to eq([boar, wolf, krynch])
    expect(EO::Skinning).to have_received(:skin).with([boar, wolf], hand: 'right').ordered
    expect(EO::Skinning).to have_received(:skin).with([krynch], hand: 'right').ordered
    expect(calls).to eq([:free_hand, [:drag, 'skinning knife'], [:store, 'baldric', 'skinning knife', true],
                         :free_both, [:drag, 'bone club'], [:store, 'baldric', 'bone club', true]])
    expect(EO::Skinning).to have_received(:stand_up).once
  end

  it 'looks for the weapon and its sheath again before each group' do
    pass([boar, krynch]).run
    expect(ensured).to eq([{ key: 'skin_weapon', inventory: [:inventory] }, { key: 'skin_sheath', check_hidden: true },
                           { key: 'skin_weapon_blunt', inventory: [:inventory] }, { key: 'skin_sheath_blunt', check_hidden: true }])
  end

  it 'does nothing, and does not stand up, when nothing is worth a try' do
    settings[:unskinnable] = ['wild boar']
    steps = pass([boar, ghost])
    expect(steps.run).to eq([])
    expect(calls).to be_empty
    expect(EO::Skinning).not_to have_received(:stand_up)
  end

  describe 'one step at a time' do
    it 'takes a group per step and says :done after the last' do
      steps = pass([boar, krynch])
      steps.start
      expect(steps.step).to eq(:skinned)
      expect(steps.skinned).to eq([boar])
      expect(steps.step).to eq(:skinned)
      expect(steps.step).to eq(:done)
      expect(steps.step).to eq(:done)
    end

    it 'leaves the hands free between steps' do
      steps = pass([boar, krynch])
      steps.start
      steps.step
      expect(held).to be_empty
    end

    it 'starts by itself on the first step' do
      expect(pass([boar]).step).to eq(:skinned)
    end

    it 'stands up on finish even when the pass was left before its end' do
      steps = pass([boar, krynch])
      steps.start
      steps.step
      steps.finish
      steps.finish
      expect(EO::Skinning).to have_received(:stand_up).once
    end

    it 'does not stand up when an error ends the pass: what follows one is for the caller' do
      allow(EO::Skinning).to receive(:skin).and_raise(Interrupt)
      expect { pass([boar]).run }.to raise_error(Interrupt)
      expect(EO::Skinning).not_to have_received(:stand_up)
    end

    it 'does not stand up on finish when nothing was started' do
      pass([boar]).finish
      expect(EO::Skinning).not_to have_received(:stand_up)
    end
  end

  describe 'without a tool' do
    it 'says so and leaves an edged group when no weapon is listed and the right hand is empty' do
      ready.delete(:skin_weapon)
      allow(EO::Skinning).to receive(:tool).and_call_original
      stub_const('GameObj', Module.new do
        define_singleton_method(:right_hand) { Struct.new(:id).new(nil) }
        define_singleton_method(:left_hand) { Struct.new(:id).new('99') }
      end)
      steps = pass([boar])
      steps.start
      expect(steps.step).to eq(:no_tool)
      expect(said).to eq([['info', " No edged skinning weapon found and nothing in your right hand. Please run setup and make sure it's listed."]])
      expect(calls).to be_empty
      expect(steps.skinned).to be_empty
      steps.finish
      expect(EO::Skinning).to have_received(:stand_up).once
    end

    it 'says so and leaves a blunt group when no blunt weapon is listed' do
      ready.delete(:skin_weapon_blunt)
      steps = pass([krynch])
      steps.start
      expect(steps.step).to eq(:no_tool)
      expect(said).to eq([['info', " No blunt weapon found. Please run setup and make sure it's listed."]])
    end

    it 'uses the right hand for an edged group when none is listed and says so' do
      ready.delete(:skin_weapon)
      right = thing.new(id: '55', name: 'rapier')
      held << right.id
      stub_const('GameObj', Module.new do
        define_singleton_method(:right_hand) { right }
        define_singleton_method(:left_hand) { Struct.new(:id).new('99') }
      end)
      steps = pass([boar])
      steps.start
      expect(steps.step).to eq(:skinned)
      expect(said).to include(['info', ' No edged skinning weapon found. Using your right hand.'])
      expect(EO::Skinning).to have_received(:skin).with([boar], hand: 'right')
    end

    it 'leaves a group when the tool cannot be drawn' do
      allow(hands).to receive(:drag)
      steps = pass([boar])
      steps.start
      expect(steps.step).to eq(:no_tool)
      expect(EO::Skinning).not_to have_received(:skin)
    end
  end

  describe 'what the game taught' do
    it 'keeps the names it could not skin, once, and saves' do
      allow(EO::Skinning).to receive(:skin).and_return(['dire wolf', 'dire wolf'])
      settings[:unskinnable] = ['wild boar']
      pass([wolf]).run
      expect(settings[:unskinnable]).to eq(['wild boar', 'dire wolf'])
      expect(saved.size).to eq(1)
    end

    it 'saves nothing when it learned nothing' do
      pass([wolf]).run
      expect(saved).to be_empty
    end
  end

  describe 'putting the tool away' do
    it 'goes to the default bag when the sheath did not take it' do
      ready[:skin_sheath] = thing.new(id: '14', name: 'full sheath')
      pass([boar]).run
      expect(calls.last(2)).to eq([[:store, 'full sheath', 'skinning knife', true], [:store, 'leather sack', 'skinning knife', false]])
    end

    it 'goes to the default bag when no sheath is listed' do
      ready.delete(:skin_sheath)
      pass([boar]).run
      expect(calls.last).to eq([:store, 'leather sack', 'skinning knife', true])
    end
  end

  describe 'a skinning bounty as the only reason to skin' do
    before { settings[:skin_bounty_only] = true }

    it 'skins nothing without one' do
      stub_const('Bounty', Module.new { define_singleton_method(:task) { Struct.new(:skin?).new(false) } })
      expect(pass([boar]).run).to eq([])
      expect(EO::Skinning).not_to have_received(:stand_up)
    end

    it 'skins only the bounty creature' do
      task = Struct.new(:skin?, :creature).new(true, 'Dire Wolf')
      stub_const('Bounty', Module.new { define_singleton_method(:task) { task } })
      expect(pass([boar, wolf]).run).to eq([wolf])
    end
  end
end
