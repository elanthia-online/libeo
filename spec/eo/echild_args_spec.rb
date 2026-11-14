# frozen_string_literal: true

require_relative '../spec_helper'

# echild.lic cannot be loaded outside Lich, so the line that picks the room
# the child is taken to is read from the file and run on its own.
RSpec.describe 'echild room argument' do
  let(:room_pattern) do
    source = File.read(File.expand_path('../../scripts/echild.lic', __dir__))
    eval(source[%r{near = Script\.current\.vars\[0\] =~ (/.*/) \? \$1 : nil}, 1])
  end

  def near(args) = args =~ room_pattern ? Regexp.last_match(1) : nil

  it 'takes a bare room id or uid' do
    expect(near('228')).to eq('228')
    expect(near('u228')).to eq('u228')
    expect(near('--test:owl 228')).to eq('228')
  end

  it 'ignores a number inside an option' do
    expect(near('--disabler=617')).to be_nil
    expect(near('--disabler:617')).to be_nil
    expect(near('--test:owl2')).to be_nil
    expect(near('--disabler=617 228')).to eq('228')
  end

  it 'is nil with no room' do
    expect(near('')).to be_nil
    expect(near('nodisable')).to be_nil
  end
end
