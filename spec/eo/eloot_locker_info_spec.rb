# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'

# Hoard.locker_info_town lives in eloot.lic, which cannot be loaded outside
# Lich, so the real method is read from the file and run against a stand-in
# for LOCKER INFO.
RSpec.describe 'eloot Hoard.locker_info_town' do
  def self.method_source
    path = File.expand_path('../../scripts/eloot.lic', __dir__)
    found = nil
    walk = lambda do |node|
      found ||= node if node.is_a?(Prism::DefNode) && node.name == :locker_info_town
      node.compact_child_nodes.each { |child| walk.call(child) if child }
    end
    walk.call(Prism.parse(File.read(path)).value)
    found.slice
  end

  # answers: what LOCKER INFO gives each time it is asked, in turn
  def hoard_answering(*answers)
    asked = []
    locker = Module.new
    locker.define_singleton_method(:info_town) do
      asked << 1
      answers.shift
    end
    stub_const('EO::Locker', locker)
    hoard = Module.new
    hoard.module_eval(self.class.method_source)
    [hoard, asked]
  end

  it 'asks once, and keeps the town it was told' do
    hoard, asked = hoard_answering("the town of Kraken's Fall", 'somewhere else')
    expect(hoard.locker_info_town).to eq("the town of Kraken's Fall")
    expect(hoard.locker_info_town).to eq("the town of Kraken's Fall")
    expect(asked.size).to eq(1)
  end

  it 'asks again when LOCKER INFO got no answer, and does not keep the nothing' do
    hoard, asked = hoard_answering(nil, "the town of Kraken's Fall")
    expect(hoard.locker_info_town).to be_nil
    expect(hoard.locker_info_town).to eq("the town of Kraken's Fall")
    expect(asked.size).to eq(2)
  end
end
