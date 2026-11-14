# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'

RSpec.describe 'EO.command and EO.result' do
  let(:sent) { [] }
  let(:waits) { [] }

  before do
    spec = self
    log = sent
    util = Module.new do
      define_singleton_method(:issue_command) { |cmd, _regex, **| log << cmd; spec.instance_variable_get(:@answers).shift }
    end
    stub_const('Lich::Util', util)
    w = waits
    EO.define_singleton_method(:waitrt?) { w << :rt }
    EO.define_singleton_method(:waitcastrt?) { w << :cast }
    EO.define_singleton_method(:sleep) { |seconds| w << seconds }
    EO.define_singleton_method(:dothistimeout) { |cmd, _t, _r| log << cmd; spec.instance_variable_get(:@answers).shift&.first }
  end

  after do
    %i[waitrt? waitcastrt? sleep dothistimeout].each { |m| EO.singleton_class.remove_method(m) }
  end

  it 'returns the answer lines of a command that ran' do
    @answers = [['You glance through the sack.']]
    expect(EO.command('look in #1', /glance/)).to eq(['You glance through the sack.'])
    expect(sent).to eq(['look in #1'])
    expect(waits).to be_empty
  end

  it 'waits out a roundtime refusal and sends the command again' do
    @answers = [['...wait 2 seconds.'], ['Roundtime: 3 sec.'], ['You glance through the sack.']]
    expect(EO.command('look in #1', /glance/)).to eq(['You glance through the sack.'])
    expect(sent).to eq(['look in #1'] * 3)
    # each wait is a settle: its sleeps are where a script's guarded sleep comes in
    expect(waits).to eq([0.2, :cast, :rt, 0.2] * 2)
  end

  it 'does the same for a single-line result' do
    @answers = [['Roundtime: 1 sec.'], ['You remove a sack.']]
    expect(EO.result('get #1', /You remove/)).to eq('You remove a sack.')
    expect(sent).to eq(['get #1', 'get #1'])
    expect(waits).to eq([0.2, :cast, :rt, 0.2])
  end

  it 'returns nil when a result never came' do
    @answers = [[nil]]
    expect(EO.result('get #1', /You remove/)).to be_nil
  end
end

RSpec.describe 'EO.stand' do
  def stub_stand(stands_after)
    sent = []
    EO.define_singleton_method(:fput) { |cmd| sent << cmd }
    EO.define_singleton_method(:standing?) { sent.size >= stands_after }
    allow(EO).to receive(:settle)
    sent
  end

  after { %i[fput standing?].each { |m| EO.singleton_class.remove_method(m) } }

  it 'stands and stops once standing' do
    sent = stub_stand(2)
    expect(EO.stand).to be(true)
    expect(sent).to eq(%w[stand stand])
  end

  it 'gives up when something keeps the character down' do
    sent = stub_stand(99)
    expect(EO.stand(tries: 3)).to be(false)
    expect(sent.size).to eq(3)
  end
end

RSpec.describe 'EO.kneel' do
  def stub_kneel(kneels_after)
    sent = []
    EO.define_singleton_method(:fput) { |cmd| sent << cmd }
    EO.define_singleton_method(:kneeling?) { sent.size >= kneels_after }
    allow(EO).to receive(:settle)
    sent
  end

  after { %i[fput kneeling?].each { |m| EO.singleton_class.remove_method(m) } }

  it 'sends nothing when already kneeling' do
    sent = stub_kneel(0)
    expect(EO.kneel).to be(true)
    expect(sent).to be_empty
  end

  it 'kneels and stops once kneeling' do
    sent = stub_kneel(2)
    expect(EO.kneel).to be(true)
    expect(sent).to eq(%w[kneel kneel])
  end

  it 'gives up after five tries when something keeps the character up' do
    sent = stub_kneel(99)
    expect(EO.kneel).to be(false)
    expect(sent.size).to eq(5)
  end
end
