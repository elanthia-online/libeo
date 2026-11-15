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
    expect { EO.helper(:stance) }.to raise_error(EO::NoHelper, /eloot lent libeo no :stance helper/)
    running[0] = nil
    expect { EO.helper(:stance) }.to raise_error(EO::NoHelper, /no script lent libeo no :stance helper/)
  end

  it "runs the library's own where the script lent none, and the script's where it did" do
    allow(EO::Own).to receive(:settle).and_return(:own)
    expect(EO.settle).to eq(:own)
    EO.use(wait: -> { :lent })
    expect(EO.settle).to eq(:lent)
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

RSpec.describe EO::Own do
  let(:sent) { [] }
  let(:answers) { [] }
  let(:shown) { [] }
  let(:state) { { hidden: false, room: Struct.new(:id, :tags).new(5, ['bank']) } }

  before do
    log = sent
    queue = answers
    out = shown
    now = state
    stub_const('Script', Class.new do
      define_singleton_method(:current) { Struct.new(:name).new('spec') }
      define_singleton_method(:run) { |*args| log << [:run, *args] }
    end)
    stub_const('Lich::Util', Class.new { define_singleton_method(:issue_command) { |text, _pattern, **opts| log << [text, opts] && queue.shift } })
    stub_const('Lich::Messaging', Class.new { define_singleton_method(:msg) { |type, text| out << [type, text] } })
    stub_const('Room', Class.new { define_singleton_method(:current) { now[:room] } })
    {
      dothistimeout: ->(text, _time, _pattern) { log << text && queue.shift }, respond: ->(text) { out << text },
      sleep: ->(_t) {}, waitrt?: -> { log << :waitrt }, waitcastrt?: -> { log << :waitcastrt },
      fput: ->(text) { log << text }, hidden?: -> { now[:hidden] }, invisible?: -> { false }
    }.each { |name, body| described_class.define_singleton_method(name, &body) }
  end

  after do
    %i[dothistimeout respond sleep waitrt? waitcastrt? fput hidden? invisible?].each { |m| described_class.singleton_class.remove_method(m) }
    EO.forget(script: 'spec')
  end

  it 'collects the lines of an answer, sending the command again after roundtime' do
    answers.push(['...wait 2 seconds.'], ['In the sack you see a gem.'])
    expect(EO.command('look in #1', /In the/, silent: true)).to eq(['In the sack you see a gem.'])
    expect(sent.map { |entry| entry.is_a?(Array) ? entry.first : entry }).to eq(['look in #1', :waitcastrt, :waitrt, 'look in #1'])
    expect(sent.first.last).to include(silent: true, quiet: false, timeout: 5)
  end

  it 'sends unseen for lines' do
    answers.push(['a line'])
    EO.lines('spell active', /Active/)
    expect(sent.first.last).to include(silent: true, quiet: true)
  end

  it 'returns the one line that answers, after any roundtime, a wait or a rash' do
    answers.push('Wait 3 sec.', 'An uncontrollable urge to scratch the rash overcomes you.', 'You pick up a gem.')
    expect(EO.result('get #1', /You pick up/)).to eq('You pick up a gem.')
    expect(sent.count('get #1')).to eq(3)
    expect(EO.result('get #1', /You pick up/)).to be_nil
    answers.push('Anything at all.')
    expect(EO.result('nod')).to eq('Anything at all.')
  end

  it 'walks with go2 out of hiding, unless already there' do
    state[:hidden] = true
    EO.go2('bank')
    EO.go2(5)
    EO.go2('furrier')
    expect(sent).to eq(['unhide', 'unhide', 'unhide', [:run, 'go2', 'furrier --disable-confirm', { quiet: true }]])
  end

  it 'says a message either way it is asked, a Hash inspected' do
    EO.say('info', 'one')
    EO.say(type: 'yellow', text: { a: 1 }, space: true)
    expect(shown).to eq([%w[info one], '', ['yellow', '{a: 1}'], ''])
  end

  it 'keeps debug messages for a script that wants them, and shows them as speech' do
    wanted = false
    EO.use(debug: -> { wanted })
    EO.say('debug', 'quiet')
    wanted = true
    EO.say(type: 'debug', text: 'heard')
    expect(shown).to eq([%w[speech heard]])
  end
end
