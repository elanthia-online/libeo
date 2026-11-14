# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'
require_relative '../../scripts/eo/loot/pass'

# ELoot.loot lives in eloot.lic, which cannot be loaded outside Lich, so the
# real method is read from the file and run against stand-ins for libeo's
# looting pass and what eloot hands it.
LOOT_SOURCE = begin
  found = nil
  walk = lambda do |node|
    found ||= node if node.is_a?(Prism::DefNode) && node.name == :loot && node.parameters&.keywords&.any?
    node.compact_child_nodes.each { |c| walk.call(c) if c }
  end
  walk.call(Prism.parse(File.read(File.expand_path('../../scripts/eloot.lic', __dir__))).value)
  found.slice
end

RSpec.describe 'eloot ELoot.loot' do
  let(:skin_enable) { true }
  let(:handed) { {} }
  let(:ran) { [] }
  let(:skin_passes) { [] }
  let(:dead) { %i[boar wolf] }
  let(:eloot) do
    spec = self
    settings = { skin_enable: skin_enable }
    mod = Module.new
    data = Struct.new(:settings).new(settings)
    mod.define_singleton_method(:data) { data }
    mod.define_singleton_method(:change_stance) { |_name| nil }
    mod.define_singleton_method(:use_coin_hand) { nil }
    loot = Module.new
    loot.define_singleton_method(:floor) { :the_floor }
    loot.define_singleton_method(:skin_pass) { |corpses| spec.skin_passes << corpses; :a_skin_pass }
    inventory = Module.new
    inventory.define_singleton_method(:return_hands) { nil }
    mod.const_set(:Loot, loot)
    mod.const_set(:Inventory, inventory)
    mod.const_set(:GameObj, Module.new { define_singleton_method(:dead) { spec.dead } })
    pass = Class.new do
      define_method(:initialize) { |context, **args| spec.handed.replace(args.merge(context: context)) }
      define_method(:run) { spec.ran << :run }
    end
    eo = Module.new
    eo.const_set(:Loot, Module.new)
    eo::Loot.const_set(:Pass, pass)
    mod.const_set(:EO, eo)
    mod.const_set(:ELoot, mod)
    mod.module_eval("def self.#{LOOT_SOURCE.sub('def self.', '')}")
    mod
  end

  it 'hands the pass every keyword it needs and none it does not know' do
    parameters = EO::Loot::Pass.instance_method(:initialize).parameters
    required = parameters.select { |kind, _| kind == :keyreq }.map(&:last)
    known = parameters.select { |kind, _| %i[key keyreq].include?(kind) }.map(&:last)
    eloot.loot
    expect(required - handed.keys).to be_empty
    expect(handed.keys - known - [:context]).to be_empty
  end

  it 'runs the pass' do
    eloot.loot
    expect(ran).to eq([:run])
  end

  it 'hands it the floor and the character\'s data' do
    eloot.loot
    expect(handed[:floor]).to eq(:the_floor)
    expect(handed[:context]).to equal(eloot.data)
  end

  it 'loots the floor unless told not to' do
    eloot.loot
    expect(handed[:floor_loot]).to be(true)
    eloot.loot(floor: false)
    expect(handed[:floor_loot]).to be(false)
  end

  it 'looks for the dead when the pass asks, or uses the ones it was given' do
    eloot.loot
    expect(handed[:corpses].call).to eq(%i[boar wolf])
    eloot.loot(corpses: [:one])
    expect(handed[:corpses].call).to eq([:one])
  end

  it 'gives the pass a skinning pass to build when skinning is on, with the dead of that moment' do
    eloot.loot(corpses: [:one])
    expect(skin_passes).to be_empty
    expect(handed[:skin].call).to eq(:a_skin_pass)
    expect(skin_passes).to eq([[:one]])
  end

  context 'with skinning off' do
    let(:skin_enable) { false }

    it 'gives it none' do
      eloot.loot
      expect(handed[:skin]).to be_nil
    end
  end
end
