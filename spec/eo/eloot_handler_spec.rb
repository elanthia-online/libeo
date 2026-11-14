# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'
require_relative '../../scripts/eo/loot/handler'

# What eloot hands libeo's Handler and what it does with its answers:
# ELoot::Inventory's methods live in eloot.lic, which cannot be loaded outside
# Lich, so the real methods are read from the file.
HANDLER_WRAPPER_NAMES = %i[handler put_away drag free_hand free_hands open_single_container store_item check_auto_closer
                           open_loot_containers return_hands].freeze

HANDLER_WRAPPERS = begin
  found = {}
  walk = lambda do |node, path|
    path += [node.constant_path.slice] if node.is_a?(Prism::ModuleNode)
    found[node.name] ||= node if node.is_a?(Prism::DefNode) && path.last == 'Inventory' && HANDLER_WRAPPER_NAMES.include?(node.name)
    node.compact_child_nodes.each { |c| walk.call(c, path) }
  end
  walk.call(Prism.parse(File.read(File.expand_path('../../scripts/eloot.lic', __dir__))).value, [])
  found
end

RSpec.describe 'eloot Inventory over EO::Loot::Handler' do
  it 'hands the handler every keyword it needs and none it does not know' do
    call = HANDLER_WRAPPERS.fetch(:handler).body.body.first
    sent = call.arguments.arguments.last.elements.map { |e| e.key.unescaped.to_sym }
    parameters = EO::Loot::Handler.instance_method(:initialize).parameters
    required = parameters.select { |kind, _| kind == :keyreq }.map(&:last)
    known = parameters.select { |kind, _| %i[key keyreq].include?(kind) }.map(&:last)
    expect(required - sent).to be_empty
    expect(sent - known).to be_empty
    # the three that are optional change what eloot does when they are left out
    expect(sent).to include(:stow, :on_tool_stow, :autoclosers_due)
  end

  describe 'the handler it builds' do
    let(:seen) { {} }
    let(:asked) { [] }
    let(:built) do
      spec = self
      eloot = Module.new
      eloot.define_singleton_method(:data) { :the_data }
      eloot.define_singleton_method(:get_command) { |*| nil }
      eloot.define_singleton_method(:wait_for_disk) { nil }
      eloot.define_singleton_method(:record_room_tool_stow) { |*| nil }
      eloot.define_singleton_method(:time_between) { |key, seconds| spec.asked << [key, seconds]; :due }
      sell = Module.new
      sell.define_singleton_method(:check_inventory) { [] }
      handler = Class.new do
        define_method(:initialize) { |context, **args| spec.seen.replace(args.merge(context: context)) }
      end
      eo = Module.new
      eo.const_set(:Loot, Module.new)
      eo::Loot.const_set(:Handler, handler)
      mod = Module.new
      mod.const_set(:ELoot, eloot)
      mod.const_set(:Sell, sell)
      mod.const_set(:EO, eo)
      mod.const_set(:Inventory, mod)
      mod.define_singleton_method(:single_drag) { |item| spec.asked << [:single_drag, item] }
      mod.module_eval(HANDLER_WRAPPERS.fetch(:handler).slice)
      mod.handler
      mod
    end

    it 'gives it the character\'s data' do
      built
      expect(seen[:context]).to eq(:the_data)
    end

    it 'puts away with eloot\'s own drag, which pauses for the player' do
      built
      seen[:stow].call(:item)
      expect(asked).to eq([[:single_drag, :item]])
    end

    it 'looks at the bags that close themselves every half minute' do
      built
      expect(seen[:autoclosers_due].call).to eq(:due)
      expect(asked).to eq([[:autoclosers, 30]])
    end
  end

  describe 'the methods' do
    let(:calls) { [] }
    let(:answers) { {} }
    let(:said) { [] }
    let(:thing) { Struct.new(:name) }
    let(:inventory) do
      log = calls
      replies = answers
      handler = Object.new
      %i[put_away drag free_hand free_hands open_single_container store_item check_auto_closer open_loot_containers
         return_hands].each do |name|
        handler.define_singleton_method(name) { |*args, **kwargs| log << [name, args, kwargs]; replies[name] }
      end
      msgs = said
      eloot = Module.new
      eloot.define_singleton_method(:msg) { |type: 'yellow', text: '', **| msgs << [type, text] }
      mod = Module.new
      mod.const_set(:ELoot, eloot)
      mod.const_set(:Inventory, mod)
      mod.define_singleton_method(:handler) { handler }
      mod.define_singleton_method(:exit) { raise SystemExit }
      HANDLER_WRAPPERS.each { |name, node| mod.module_eval(node.slice) unless name == :handler }
      mod
    end

    it 'hands each call on with what it was given' do
      inventory.put_away(:hand)
      inventory.free_hands(both: true)
      inventory.open_single_container(:sack)
      inventory.store_item(:bag, :item, true)
      inventory.store_item(:bag, :item)
      inventory.check_auto_closer
      inventory.open_loot_containers([:a])
      expect(calls).to eq([
                            [:put_away, [:hand], {}], [:free_hands, [], { both: true }], [:open_single_container, [:sack], {}],
                            [:store_item, [:bag, :item, true], {}], [:store_item, [:bag, :item, false], {}],
                            [:check_auto_closer, [], {}], [:open_loot_containers, [[:a]], {}]
                          ])
    end

    it 'answers what the handler answers for a drag, with the side' do
      answers[:drag] = true
      expect(inventory.drag(:item, 'left')).to be(true)
      expect(calls.last).to eq([:drag, [:item, 'left'], {}])
      expect(inventory.drag(:item)).to be(true)
      expect(calls.last).to eq([:drag, [:item, 'hand'], {}])
    end

    it 'says so and ends the script when neither hand is usable' do
      answers[:drag] = :crippled
      expect { inventory.drag(:item) }.to raise_error(SystemExit)
      expect(said.last).to eq(['yellow', ' Neither hand is usable. Looks like you need an Empath!'])
      answers[:free_hand] = :crippled
      expect { inventory.free_hand }.to raise_error(SystemExit)
    end

    it 'says so and ends the script when an item cannot be picked up' do
      answers[:drag] = :overloaded
      expect { inventory.drag(thing.new('blue ruby')) }.to raise_error(SystemExit)
      expect(said.last).to eq(['yellow', ' Unable to pick up the blue ruby. Exiting...'])
    end

    it 'goes on when a hand was freed' do
      expect { inventory.free_hand }.not_to raise_error
    end

    it 'gives the hands back through its own drag, which ends the script when it must' do
      inventory.return_hands
      expect(calls.last[0]).to eq(:return_hands)
      back = calls.last[2][:drag]
      answers[:drag] = :crippled
      expect { back.call(:item, 'right') }.to raise_error(SystemExit)
      expect(calls.last).to eq([:drag, [:item, 'right'], {}])
    end
  end
end
