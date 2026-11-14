# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'

# ecleanse.lic cannot be loaded outside Lich, so Action.recover is read from
# the file and run against stand-ins for the disarm module and the game.
RSpec.describe 'ecleanse Action.recover' do
  def self.method_source
    path = File.expand_path('../../scripts/ecleanse.lic', __dir__)
    found = nil
    walk = lambda do |node|
      found ||= node if node.is_a?(Prism::DefNode) && node.name == :recover
      node.compact_child_nodes.each { |child| walk.call(child) if child }
    end
    walk.call(Prism.parse(File.read(path)).value)
    found.slice
  end

  let(:log) { [] }

  # servant: whether the servant brings the weapon back
  def recover(servant:)
    log = self.log
    disarms = Module.new
    disarms.define_singleton_method(:tracked?) { |_id| true }
    disarms.define_singleton_method(:prepare) { |_policy| log << 'cast 213, 1011' && %i[s213 s1011] }
    disarms.define_singleton_method(:servant) { servant }
    disarms.define_singleton_method(:remove) { |id| log << "remove #{id}" }
    disarms.define_singleton_method(:stop) { |stops| log << "stop #{stops.join(',')}" }
    disarms.define_singleton_method(:await_bonded) { |*| true }
    disarms.define_singleton_method(:restore_hands) { |*| nil }
    stub_const('EO', Module.new)
    stub_const('EO::Cleanse', Module.new)
    stub_const('EO::Cleanse::Disarms', disarms)
    EO.define_singleton_method(:say) { |*| nil }
    EO.define_singleton_method(:go2) { |*, **| nil }
    EO.define_singleton_method(:settle) { |*| nil }

    entry = { room: Struct.new(:id, :title).new(1, ['r']), noun: 'sword', known_ids: [], disarm_id: 7 }
    data = Struct.new(:recover_stuff).new({ 1 => entry })
    action = Module.new
    action.const_set(:System, Module.new { def self.scripts_pause = nil })
    action.const_set(:Ecleanse, Struct.new(:data).new(data))
    action.define_singleton_method(:brace) { nil }
    action.define_singleton_method(:policy) { :policy }
    action.define_singleton_method(:settings) { { recover_disarmed: true } }
    action.module_eval("Action = self\n#{self.class.method_source}")
    action.recover(1)
    log
  end

  it 'stops what it cast when the servant brings the weapon back' do
    expect(recover(servant: true)).to eq(['cast 213, 1011', 'remove 7', 'stop s213,s1011'])
  end

  it 'stops what it cast when it recovers the weapon itself' do
    expect(recover(servant: false)).to include('stop s213,s1011')
  end
end
