# frozen_string_literal: true

require 'prism'
require_relative '../spec_helper'

# Ewaggle.get_target_info lives in ewaggle.lic, which cannot be loaded outside
# Lich, so the real method is read from the file and run against a stand-in
# for SPELL ACTIVE.
RSpec.describe 'ewaggle get_target_info' do
  def self.method_source
    path = File.expand_path('../../scripts/ewaggle.lic', __dir__)
    found = nil
    walk = lambda do |node|
      found ||= node if node.is_a?(Prism::DefNode) && node.name == :get_target_info
      node.compact_child_nodes.each { |child| walk.call(child) if child }
    end
    walk.call(Prism.parse(File.read(path)).value)
    found.slice
  end

  let(:said) { [] }

  # active: what SPELL ACTIVE came back as; skip: the skip_not_sharing setting
  def info_for(active, skip: false)
    log = said
    casting = Module.new
    casting.define_singleton_method(:active_on) { |_target| active }
    stub_const('EO::Casting', casting)
    messaging = Module.new
    messaging.define_singleton_method(:msg) { |_kind, text| log << text }
    stub_const('Lich::Messaging', messaging)
    settings = { skip_not_sharing: skip }
    ewaggle = Module.new
    ewaggle.define_singleton_method(:data) { Struct.new(:settings).new(settings) }
    ewaggle.define_singleton_method(:respond) { |*| nil }
    stub_const('Ewaggle', ewaggle)
    holder = Module.new
    holder.define_singleton_method(:respond) { |*| nil }
    holder.module_eval(self.class.method_source)
    holder.get_target_info('hypate')
  end

  it 'skips a character the game gave no answer about, and says why' do
    expect(info_for(nil)).to be_nil
    expect(said.join).to include('No answer to SPELL ACTIVE HYPATE').and include('Hypate')
  end

  it 'gives back what a sharing character has active' do
    active = { 'sharing' => true, '101' => 240.0 }
    expect(info_for(active)).to eq(active)
    expect(said).to be_empty
  end

  it 'casts once at a character who does not share, unless told to skip them' do
    private_one = { 'sharing' => false }
    expect(info_for(private_one)).to eq(private_one)
    expect(said.join).to include('not sharing spell information')
    expect(info_for(private_one, skip: true)).to be_nil
  end
end
