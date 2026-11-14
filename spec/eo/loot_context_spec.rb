# frozen_string_literal: true

require 'prism'
require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/carry'
require_relative '../../scripts/eo/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/loot/context'

RSpec.describe EO::Loot::Context do
  let(:said) { [] }
  let(:saved) { [] }
  let(:settings) { { crumbly: [], auto_close: [] } }
  let(:item) { Struct.new(:name).new('a brittle rock') }
  let(:context) do
    said_to = said
    saved_to = saved
    described_class.new(settings: settings, say: ->(type:, text:) { said_to << [type, text] }, save: -> { saved_to << true })
  end

  it 'starts with empty lists and nothing in hand' do
    expect(context.disk_full).to eq({})
    expect([context.checked_bags, context.sell_containers, context.weapon_inv]).to eq([[], [], []])
    expect(context.right_hand).to be_nil
  end

  it 'takes the state a caller already has' do
    ctx = described_class.new(settings: settings, right_hand: 'sword', loot_keep_regex: /gem/)
    expect(ctx.right_hand).to eq('sword')
    expect(ctx.loot_keep_regex).to eq(/gem/)
  end

  it 'refuses a name that is not looting state' do
    expect { described_class.new(settings: settings, silver: 5) }.to raise_error(ArgumentError, /unknown looting state: silver/)
  end

  it 'shares the settings it was given' do
    expect(context.settings).to equal(settings)
  end

  it 'keeps the stow it was given, else makes one that learns through it' do
    mine = EO::Stow.new
    expect(described_class.new(settings: settings, stow: mine).stow).to equal(mine)

    context.stow.instance_variable_get(:@learned).call(:crumbly, item)
    expect(settings[:crumbly]).to eq(['a brittle rock'])
  end

  describe '#learn' do
    it 'adds a crumbly item to the settings, says so and saves' do
      context.learn(:crumbly, item)
      expect(settings[:crumbly]).to eq(['a brittle rock'])
      expect(said).to eq([['info', ' This item was crumbly, adding to list']])
      expect(saved.size).to eq(1)
    end

    it 'adds a bag that closes itself, says so and saves' do
      context.learn(:auto_close, Struct.new(:name).new('leather sack'))
      expect(settings[:auto_close]).to eq(['leather sack'])
      expect(said).to eq([['info', ' leather sack must be an autocloser, adding to list.']])
      expect(saved.size).to eq(1)
    end

    it 'starts a list the settings do not have yet' do
      bare = described_class.new(settings: {})
      bare.learn(:crumbly, item)
      expect(bare.settings[:crumbly]).to eq(['a brittle rock'])
    end

    it 'hands an unlootable item to the caller and changes nothing else' do
      handed = []
      ctx = described_class.new(settings: settings, unlootable: ->(obj) { handed << obj.name })
      ctx.learn(:unlootable, item)
      expect(handed).to eq(['a brittle rock'])
      expect(settings).to eq(crumbly: [], auto_close: [])
    end

    it 'does nothing for what it does not know' do
      expect { context.learn(:other, item) }.not_to(change { settings.dup })
      expect(said).to be_empty
    end
  end

  it 'says and saves nothing without a place to' do
    bare = described_class.new(settings: {})
    expect { bare.say(type: 'info', text: 'x') }.not_to raise_error
    expect { bare.save }.not_to raise_error
  end

  # What eloot keeps these in: its ELoot::Data. If a name is dropped or
  # renamed there, a pass handed ELoot.data stops working, so it is read
  # from the file.
  it 'names only state that eloot keeps in ELoot::Data' do
    path = File.expand_path('../../scripts/eloot.lic', __dir__)
    data = nil
    walk = lambda do |node|
      data ||= node if node.is_a?(Prism::ClassNode) && node.name == :Data
      node.compact_child_nodes.each { |child| walk.call(child) if child }
    end
    walk.call(Prism.parse(File.read(path)).value)

    kept = data.body.body.filter_map do |node|
      next unless node.is_a?(Prism::CallNode) && node.name == :attr_accessor

      node.arguments.arguments.map(&:unescaped).map(&:to_sym)
    end.flatten
    expect(described_class::STATE + described_class::READS - kept).to be_empty
  end
end
