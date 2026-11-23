# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../scripts/eo/helpers'
require_relative '../../scripts/eo/posture'

# The libeo files are loaded by libeo.lic inside Lich. Specs load the one
# file under test and stand in for the Lich globals it touches with
# stub_const, so nothing here needs a running Lich. Fakes more than one spec
# needs go in this file.

# A running script that has lent the library its helpers. `sent` collects
# every command; `answers` maps a command (a String, or a Regexp it matches)
# to the lines the game gives back, each used once when given as an Array of
# Arrays. A command with no answer gets no lines.
RSpec.shared_context 'a script lending helpers' do
  let(:sent) { [] }
  let(:said) { [] }
  let(:went) { [] }
  let(:answers) { {} }

  def answer_to(command)
    key = answers.keys.find { |k| k.is_a?(Regexp) ? command =~ k : command == k }
    lines = answers[key]
    lines = lines.shift if lines.is_a?(Array) && lines.first.is_a?(Array)
    Array(lines)
  end

  before do
    stub_const('Script', Class.new { define_singleton_method(:current) { Struct.new(:name).new('spec') } })
    EO.use(
      command: ->(text, _pattern = nil, **) { sent << text && answer_to(text) },
      result: ->(text, _pattern = nil, **) { sent << text && answer_to(text).first },
      say: ->(type:, text:, **) { said << [type, text] },
      wait: -> { sent << :wait },
      go: ->(place) { went << place }
    )
  end

  after { EO.forget(script: 'spec') }
end

# Lich's Mana.pulse, noting in `pulses` each spell it was asked about.
RSpec.shared_context 'Lich mana' do
  let(:pulses) { [] }

  before do
    asked = pulses
    stub_const('Lich::Gemstone::Mana', Class.new { define_singleton_method(:pulse) { |spell = nil, **| asked << spell && false } })
  end
end

# Standing and kneeling are tried and answered true, except in a spec
# marked posture: true, which is about them.
RSpec.configure do |config|
  config.before do |example|
    allow(EO).to receive_messages(stand: true, kneel: true) unless example.metadata[:posture]
  end
end
