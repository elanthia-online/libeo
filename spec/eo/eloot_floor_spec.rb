# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'
require_relative '../../scripts/eo/loot/floor'

# What eloot hands libeo's Floor and how it calls it: ELoot::Loot.floor and the
# methods beside it live in eloot.lic, which cannot be loaded outside Lich, so
# the real methods are read from the file.
FLOOR_WRAPPER_NAMES = %i[floor bag_loot box_loot_ground loot_all loot_regular loot_specials policy reject_invalid_loot
                         should_grab_item? valid_objs invalid_objs room weigh_room].freeze

FLOOR_WRAPPERS = begin
  found = {}
  walk = lambda do |node, inside|
    inside ||= node.is_a?(Prism::ModuleNode) && node.constant_path.slice == 'Loot'
    found[node.name] ||= node if inside && node.is_a?(Prism::DefNode) && FLOOR_WRAPPER_NAMES.include?(node.name)
    node.compact_child_nodes.each { |c| walk.call(c, inside) }
  end
  walk.call(Prism.parse(File.read(File.expand_path('../../scripts/eloot.lic', __dir__))).value, false)
  found
end

RSpec.describe 'eloot ELoot::Loot.floor' do
  it 'hands Floor every keyword it needs and none it does not know' do
    sent = FLOOR_WRAPPERS.fetch(:floor).body.body.first.arguments.arguments.last.elements.map { |e| e.key.unescaped.to_sym }
    parameters = EO::Loot::Floor.instance_method(:initialize).parameters
    required = parameters.select { |kind, _| kind == :keyreq }.map(&:last)
    known = parameters.select { |kind, _| %i[key keyreq].include?(kind) }.map(&:last)
    expect(required - sent).to be_empty
    expect(sent - known).to be_empty
  end

  describe 'the methods that hand a call on' do
    let(:answers) { {} }
    let(:calls) { [] }
    let(:loot) do
      log = calls
      replies = answers
      floor = Object.new
      FLOOR_WRAPPER_NAMES.each do |name|
        next if name == :floor

        floor.define_singleton_method(name) { |*args, **kwargs| log << [name, args, kwargs]; replies[name] }
      end
      mod = Module.new
      mod.define_singleton_method(:floor) { floor }
      mod.const_set(:Loot, mod)
      FLOOR_WRAPPERS.each { |name, node| mod.module_eval(node.slice) unless name == :floor }
      mod.define_singleton_method(:exit) { raise SystemExit }
      mod
    end

    it 'calls the floor method of the same name with what it was given' do
      loot.bag_loot(:bag)
      loot.loot_all([:a])
      loot.loot_regular([:a], 'Box', :chest, sell_recovered: true, location: 'town', data: {})
      loot.loot_specials([:a], box: :chest)
      loot.reject_invalid_loot([:a])
      loot.valid_objs([:a])
      loot.invalid_objs([:a])
      loot.should_grab_item?(:thing)
      loot.policy
      loot.room
      loot.weigh_room
      expect(calls).to eq([
                            [:bag_loot, [:bag], {}], [:loot_all, [[:a]], {}],
                            [:loot_regular, [[:a], 'Box', :chest], { sell_recovered: true, location: 'town', data: {} }],
                            [:loot_specials, [[:a]], { box: :chest }], [:reject_invalid_loot, [[:a]], {}], [:valid_objs, [[:a]], {}],
                            [:invalid_objs, [[:a]], {}], [:should_grab_item?, [:thing], {}], [:policy, [], {}], [:room, [], {}],
                            [:weigh_room, [], {}]
                          ])
    end

    it 'ends the script when the floor says the coins cannot be held' do
      answers[:box_loot_ground] = :coins_full
      expect { loot.box_loot_ground }.to raise_error(SystemExit)
    end

    it 'goes on when the floor was done' do
      expect { loot.box_loot_ground }.not_to raise_error
    end
  end
end
