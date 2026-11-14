# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/casting'

RSpec.describe EO::Casting, '.active_on' do
  let(:spell) { Struct.new(:name, :num) }

  # lines: what SPELL ACTIVE gets back in time
  def active_with(lines)
    util = Module.new
    util.define_singleton_method(:quiet_command_xml) { |*| lines }
    stub_const('Lich::Util', util)
    spells = [spell.new('Spirit Warding I', 101), spell.new('Spirit Barrier', 102)]
    stub_const('Spell', Class.new { define_singleton_method(:list) { spells } })
    described_class.active_on('hypate')
  end

  it 'is nil when the game gave no answer in time, which is not "no spells"' do
    expect(active_with([])).to be_nil
  end

  it 'reads the spells and their minutes' do
    lines = ['Hypate currently has the following active effects:', 'Spells:',
             '  Spirit Warding I ................ 04:01:01', '  Spirit Barrier ...... Indefinite']
    expect(active_with(lines)).to eq('sharing' => true, '101' => 241.01666666666668, '102' => 599.0)
  end

  it 'says so when the character keeps spell information private' do
    expect(active_with(['Hypate has spell sharing disabled.'])).to eq('sharing' => false)
  end

  it 'is sharing, with no spells, for an answer that lists none' do
    expect(active_with(['Hypate currently has the following active effects:'])).to eq('sharing' => true)
  end
end
