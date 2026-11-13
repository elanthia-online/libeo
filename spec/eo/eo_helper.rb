# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../scripts/eo/helpers'

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
      say: ->(type:, text:, **) { said << [type, text] }
    )
  end

  after { EO.forget(script: 'spec') }
end
