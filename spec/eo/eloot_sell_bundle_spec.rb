# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'

# Sell.sell_bundle lives in eloot.lic, which cannot be loaded outside Lich.
# The real method is read from the file and run against a simulated pair of
# hands and furrier.
SellBundleThing = Struct.new(:id, :name)

RSpec.describe 'eloot Sell.sell_bundle' do
  def self.method_source
    path = File.expand_path('../../scripts/eloot.lic', __dir__)
    found = nil
    walk = lambda do |node|
      found ||= node if node.is_a?(Prism::DefNode) && node.name == :sell_bundle
      node.compact_child_nodes.each { |c| walk.call(c) if c }
    end
    walk.call(Prism.parse(File.read(path)).value)
    found.slice
  end

  # skins: how many skins the bundle holds; accept: does the furrier buy.
  def run_bundle(skins:, accept:, answer_remove: true)
    sim = Struct.new(:hands, :skins, :calls, keyword_init: true).new(
      hands: { right: SellBundleThing.new('1', 'bundle of hides'), left: SellBundleThing.new(nil, 'Empty') },
      skins: skins, calls: 0
    )
    empty = SellBundleThing.new(nil, 'Empty')
    mod = Module.new
    mod.const_set(:BUNDLE_MISSES, 3)
    elo = Module.new
    elo.define_singleton_method(:in_hand?) { |obj| sim.hands.values.any? { |h| h.id && h.id == obj.id } }
    elo.define_singleton_method(:data) { Struct.new(:silver_breakdown).new({}) }
    gobj = Module.new
    gobj.define_singleton_method(:right_hand) { sim.hands[:right] }
    gobj.define_singleton_method(:left_hand) { sim.hands[:left] }
    sell = Module.new
    sell.define_singleton_method(:sell_item) do |item, *|
      next if item.nil? || item.name == 'Empty'

      sim.hands.each { |k, h| sim.hands[k] = empty if h.equal?(item) } if accept
    end
    mod.const_set(:ELoot, elo)
    mod.const_set(:GameObj, gobj)
    mod.const_set(:Sell, sell)
    mod.define_singleton_method(:dothistimeout) do |_cmd, *|
      sim.calls += 1
      raise 'bundle remove repeated without end' if sim.calls > 25
      next nil unless answer_remove
      next nil unless sim.hands[:left].id.nil?

      if sim.skins > 2
        sim.skins -= 1
        sim.hands[:left] = SellBundleThing.new("s#{sim.skins}", 'hide')
        'You remove a hide from your bundle.'
      else
        sim.hands[:left] = SellBundleThing.new('s0', 'hide')
        'Those were the last two hides in the bundle.'
      end
    end
    mod.module_eval(self.class.method_source)
    mod.sell_bundle(sim.hands[:right])
    sim
  end

  it 'sells every skin when the furrier buys' do
    sim = run_bundle(skins: 5, accept: true)
    expect(sim.hands.values.map(&:name)).to eq(%w[Empty Empty])
  end

  it 'stops when the furrier refuses a skin instead of asking again and again' do
    sim = run_bundle(skins: 5, accept: false)
    expect(sim.calls).to be <= 2
  end

  it 'stops when the last two skins are refused' do
    sim = run_bundle(skins: 2, accept: false)
    expect(sim.calls).to eq(1)
  end

  it 'gives up after three unanswered BUNDLE REMOVE commands' do
    sim = run_bundle(skins: 5, accept: true, answer_remove: false)
    expect(sim.calls).to eq(3)
  end
end
