# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/helpers'

RSpec.describe 'EO.use' do
  let(:running) { ['eloot'] }

  before do
    name = running
    stub_const('Script', Class.new { define_singleton_method(:current) { name.first && Struct.new(:name).new(name.first) } })
  end

  after { %w[eloot ebounty].each { |script| EO.forget(script: script) } }

  it "calls the running script's helper with the arguments untouched" do
    seen = []
    EO.use(command: ->(*args, **opts) { seen << [args, opts] && ['a line'] })

    expect(EO.command('look in #1', /In the/, silent: true)).to eq(['a line'])
    expect(seen).to eq([[['look in #1', /In the/], { silent: true }]])
  end

  it 'keeps each script to its own helpers' do
    EO.use(script: 'eloot', wait: -> { :eloot_wait })
    EO.use(script: 'ebounty', wait: -> { :ebounty_wait })

    expect(EO.settle).to eq(:eloot_wait)
    running[0] = 'ebounty'
    expect(EO.settle).to eq(:ebounty_wait)
  end

  it 'names each of the five by what it does: command, result, wait, go, say' do
    EO.use(command: -> { :command }, result: -> { :result }, wait: -> { :wait }, go: ->(place) { place }, say: ->(type, text) { [type, text] })

    expect([EO.command, EO.result, EO.settle, EO.go2('bank'), EO.say('info', 'hello')]).to eq([:command, :result, :wait, 'bank', %w[info hello]])
  end

  it 'adds to what was lent before, and replaces a helper lent again' do
    EO.use(wait: -> { :first })
    EO.use(go: ->(place) { place }, wait: -> { :second })

    expect(EO.settle).to eq(:second)
    expect(EO.go2(7)).to eq(7)
  end

  it 'lends under any other name too' do
    EO.use(stance: ->(name) { "stance #{name}" })

    expect(EO.helper?(:stance)).to be(true)
    expect(EO.helper(:stance).call('defensive')).to eq('stance defensive')
    expect(EO.helper?(:pulse)).to be(false)
  end

  it 'says which helper is missing, and for which script' do
    expect { EO.result('get #1', /You/) }.to raise_error(EO::NoHelper, /eloot lent libeo no :result helper/)
    running[0] = nil
    expect { EO.settle }.to raise_error(EO::NoHelper, /no script lent libeo no :wait helper/)
  end

  it 'refuses what cannot be called' do
    expect { EO.use(wait: 'wait_rt') }.to raise_error(ArgumentError, /not callable: wait/)
  end

  it 'forgets what a script lent' do
    EO.use(wait: -> { :wait })
    EO.forget

    expect(EO.helper?(:wait)).to be(false)
  end
end
