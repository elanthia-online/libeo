# frozen_string_literal: true

require_relative 'eo_helper'

RSpec.describe 'EO.stand and EO.kneel', :posture do
  include_context 'a script lending helpers'

  let(:state) { { standing: false, kneeling: false, held: 0 } }
  let(:fputs) { [] }

  before do
    now = state
    log = fputs
    EO.define_singleton_method(:standing?) { now[:standing] }
    EO.define_singleton_method(:kneeling?) { now[:kneeling] }
    EO.define_singleton_method(:fput) do |cmd|
      log << cmd
      next if (now[:held] -= 1) >= 0

      now[cmd == 'stand' ? :standing : :kneeling] = true
    end
  end

  after { %i[standing? kneeling? fput].each { |m| EO.singleton_class.remove_method(m) } }

  it 'sends nothing when already there' do
    state.merge!(standing: true, kneeling: true)
    expect([EO.stand, EO.kneel]).to eq([true, true])
    expect(fputs).to be_empty
  end

  it 'tries again, waiting between, until it works' do
    state[:held] = 2
    expect(EO.stand).to be(true)
    expect(fputs).to eq(%w[stand stand stand])
    expect(sent).to eq(%i[wait wait wait])
  end

  it 'gives up after five tries, or as many as asked' do
    state[:held] = 100
    expect(EO.kneel).to be(false)
    expect(EO.stand(tries: 2)).to be(false)
    expect(fputs).to eq(%w[kneel] * 5 + %w[stand] * 2)
  end
end
