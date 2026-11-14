# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'

# eloot.lic cannot be loaded outside Lich, so this reads the `when` list of its
# top-level command dispatcher from the source and asks which branch each
# command line reaches. Only literal strings and regexps are evaluated.
RSpec.describe 'eloot command dispatch' do
  def self.branches
    path = File.expand_path('../../scripts/eloot.lic', __dir__)
    found = nil
    walk = lambda do |node|
      next unless node

      found ||= node if node.is_a?(Prism::CaseNode) && node.predicate&.slice == 'Script.current.vars[0]'
      node.compact_child_nodes.each { |child| walk.call(child) }
    end
    walk.call(Prism.parse(File.read(path)).value)
    found.conditions.map do |w|
      [w.conditions.map { |c| c.slice[0, 40] }.join(', '),
       w.conditions.map { |c| c.is_a?(Prism::StringNode) || c.is_a?(Prism::RegularExpressionNode) ? eval(c.slice) : nil }]
    end
  end

  let(:branches) { self.class.branches }

  def reached(line)
    branches.find { |_label, tests| tests.any? { |t| t && t === line } }&.first
  end

  it 'finds the dispatcher' do
    expect(branches.size).to be > 10
  end

  [
    'settings sell_locksmith_pool on',
    'settings always_check_pool on',
    'settings sell_locksmith_pool_tip 500',
    'settings debug on',
    'settings debug_file off',
    'settings sell_exclude "pool cue"',
    'settings sell_exclude "debug"',
    'setup skin_enable on'
  ].each do |line|
    it "sends #{line.inspect} to the settings branch" do
      expect(reached(line)).to match(/settings\|setup|settings/)
    end
  end

  it 'still sends bare pool and debug to their own branches' do
    expect(reached('pool')).to eq('/pool/')
    expect(reached('debug')).to eq('/debug/')
  end
end
