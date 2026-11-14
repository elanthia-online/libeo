# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/brooch'

# The brooch's game text is from a character's logs (2026-10-23) and an
# ANALYZE pasted by its owner.
ANALYZE = <<~TEXT.lines.map(&:chomp)
  You analyze the quintuple orb brooch and sense that the creator has provided the following information:
  The quintuple orb brooch is a Rings of Lumnis event prize.  It has been used in the following number of runs during the Rings of Lumnis:
    Planar: 105, resulting in +400 field experience capacity
    Spiritual: 1,250, resulting in the ability to instantly absorb 869 experience
    Elemental: 0, resulting in the 0% chance to reroll various checks while on Adventurer's Guild tasks
    Chaos: 105, resulting in a bonus of 400 + up to a 10% bonus when used for other orbs
    Order: 105, resulting in +400 bounty points when turning in Adventurer's Guild tasks
  These bonuses are only active while the brooch's effect is active or when triggered and it is not on cooldown.  It is currently set to Chaos, which will use the Elemental benefit when next activated.
  Daily uses reset at midnight.  You have used each orb:
    Planar: 2 out of 2
    Spiritual: 3 out of 5
    Elemental: 0 out of 0
    Chaos: 1 out of 2
    Order: 2 out of 2
  The following verbs are available to use with it: rub, turn, tap, cover, tickle, spin, push, touch, and pull.
  [SYNTAX: WHISPER {my} BROOCH [{CHAOS} or {ELEMENT} or {ORDER} or {PLANAR} or {SPIRIT}]
TEXT

RSpec.describe EO::Brooch do
  describe '.parse' do
    let(:status) { described_class.parse(ANALYZE) }

    it 'reads the orb it is on and what chaos will give' do
      expect(status.current).to eq(:chaos)
      expect(status.chaos_gives).to eq(:element)
    end

    it 'reads the rubs left today, not the run counts' do
      expect(status.left(:planar)).to eq(0)
      expect(status.left(:spirit)).to eq(2)
      expect(status.left(:element)).to eq(0)
      expect(status.left(:chaos)).to eq(1)
      expect(status.left(:order)).to eq(0)
    end
  end

  describe '.rub' do
    def rub_answer(line)
      allow(EO).to receive(:result).and_return(line)
      described_class.rub
    end

    it 'names the orb whose energy took hold' do
      expect(rub_answer('You trace the central orb of red in your brooch and your fingertips begin to tingle as planar energy flows into you.  ' \
                        "Within seconds, you feel Lumnis' Enlightenment course through your veins.")).to eq(:planar)
      expect(rub_answer('You trace the central orb of blue in your brooch and your fingertips begin to tingle as spiritual energy flows into you.')).to eq(:spirit)
    end

    it 'names the orb a chaos rub gave' do
      line = 'You trace the central orb of black in your brooch and your fingertips begin to tingle as chaotic energy flows into you.  ' \
             "Within seconds, you feel Lumnis' Divergence course through your veins, but it is fleeting as spiritual energy soon " \
             "replaces it and you feel Lumnis' Vigor take hold."
      expect(rub_answer(line)).to eq(:spirit)
    end

    it 'knows a spent orb' do
      expect(rub_answer('The quintuple orb brooch ebbs weakly, but nothing further happens.')).to eq(:spent)
    end
  end

  describe '.analyze' do
    it 'captures from the first line to the SYNTAX line, not to a prompt Lich strips' do
      expect(ANALYZE.first).to match(described_class::ANALYZE_START)
      expect(ANALYZE.last).to match(described_class::ANALYZE_END)
      util = class_double('Lich::Util').as_stubbed_const
      expect(util).to receive(:issue_command)
        .with('analyze my brooch', described_class::ANALYZE_START, described_class::ANALYZE_END, hash_including(usexml: false))
        .and_return(ANALYZE)
      expect(described_class.parse(described_class.analyze).left(:spirit)).to eq(2)
    end
  end

  describe '.use' do
    let(:sent) { [] }
    let(:analyzed) { [] }
    let(:text) { [ANALYZE] }
    let(:rubbed) { ['as spiritual energy flows into you'] }

    before do
      spec = self
      described_class.forget
      allow(described_class).to receive(:with_brooch) { |&block| block.call }
      allow(described_class).to receive(:analyze) { (spec.analyzed << 1) && (spec.text.size > 1 ? spec.text.shift : spec.text.first) }
      allow(EO).to receive(:result) do |cmd, _re, **|
        spec.sent << cmd
        next (spec.rubbed.size > 1 ? spec.rubbed.shift : spec.rubbed.first) if cmd == 'rub my brooch'

        "[Your quintuple orb brooch is now attuned to the #{cmd.split.last} ring.  You can see this change in LOOK.]"
      end
    end

    def analyze_with(changes)
      ANALYZE.map { |line| changes.reduce(line) { |l, (from, to)| l.sub(from, to) } }
    end

    it 'whispers to the orb and rubs it while it has a rub left' do
      expect(described_class.use(:spirit)).to eq(:spirit)
      expect(sent).to eq(['whisper my brooch chaos', 'whisper my brooch spirit', 'rub my brooch']) # chaos first, for ANALYZE
    end

    it 'asks ANALYZE once, then counts its own rubs' do
      2.times { described_class.use(:spirit) }
      expect(analyzed.size).to eq(1)
      expect(described_class.left(:spirit)).to eq(0)
    end

    it 'does nothing when the orb is spent and chaos gives something else, however often asked' do
      3.times { expect(described_class.use(:planar)).to eq(:none) }
      expect(sent).to eq(['whisper my brooch chaos'])
      expect(analyzed.size).to eq(1)
    end

    it 'asks ANALYZE once more when its own count runs an orb out, and not again that day' do
      text << analyze_with('Spiritual: 3 out of 5' => 'Spiritual: 5 out of 5')
      2.times { described_class.use(:spirit) }
      2.times { expect(described_class.use(:spirit)).to eq(:none) }
      expect(analyzed.size).to eq(2)
      expect(sent.count('rub my brooch')).to eq(2)
    end

    it 'finds the rubs a hand-made count missed when ANALYZE shows more left' do
      text << analyze_with('Spiritual: 3 out of 5' => 'Spiritual: 3 out of 8')
      3.times { expect(described_class.use(:spirit)).to eq(:spirit) }
      expect(analyzed.size).to eq(2)
    end

    it "takes the brooch's refusal for the orb being spent, with no ANALYZE" do
      rubbed.replace(['The quintuple orb brooch ebbs weakly, but nothing further happens.'])
      expect(described_class.use(:spirit)).to eq(:spent)
      expect(described_class.use(:spirit)).to eq(:none)
      expect(sent).to eq(['whisper my brooch chaos', 'whisper my brooch spirit', 'rub my brooch'])
      expect(analyzed.size).to eq(1)
    end

    it 'whispers for chaos and rubs it when it gives the spent orb' do
      text.replace([analyze_with('use the Elemental benefit' => 'use the Planar benefit')])
      rubbed.replace(['as chaotic energy flows into you.  Within seconds it is fleeting as planar energy soon replaces it'])
      expect(described_class.use(:planar)).to eq(:planar)
      expect(sent).to eq(['whisper my brooch chaos', 'whisper my brooch chaos', 'rub my brooch', 'whisper my brooch chaos']) # ANALYZE again after the chaos rub
    end

    it 'asks what chaos gives again only after a chaos rub, right after it' do
      text.replace([analyze_with('use the Elemental benefit' => 'use the Planar benefit', 'Chaos: 1 out of 2' => 'Chaos: 0 out of 2')])
      rubbed.replace(['as chaotic energy flows into you.  Within seconds it is fleeting as planar energy soon replaces it'])
      2.times { expect(described_class.use_chaos_if(:element)).to eq(:none) }
      expect(analyzed.size).to eq(1)
      described_class.use_chaos_if(:planar)
      expect(analyzed.size).to eq(2)
    end

    it 'does not rub when the whisper is not answered for that orb' do
      allow(EO).to receive(:result) do |cmd, _re, **|
        sent << cmd
        'You discreetly whisper your desire to have your brooch shift, but it is unresponsive.'
      end
      expect(described_class.use(:spirit)).to eq(:none)
      expect(sent).to eq(['whisper my brooch chaos', 'whisper my brooch spirit'])
    end

    it 'takes "already centered" by the colour of the orb' do
      answers = { 'whisper my brooch spirit' => 'but it is already centered on the blue orb.', 'rub my brooch' => 'as spiritual energy flows into you' }
      allow(EO).to receive(:result) { |cmd, _re, **| answers[cmd] }
      expect(described_class.use(:spirit)).to eq(:spirit)
      answers['whisper my brooch spirit'] = 'but it is already centered on the red orb.'
      expect(described_class.use(:spirit)).to eq(:none)
    end

    it 'starts the count over on a new Eastern day' do
      described_class.use(:spirit)
      allow(EO).to receive(:eastern_day).and_return('2099-01-01')
      described_class.use(:spirit)
      expect(analyzed.size).to eq(2)
    end

    it 'names order from the rub that says ordered energy' do
      allow(EO).to receive(:result) do |cmd, _re, **|
        cmd == 'rub my brooch' ? 'You trace the central orb of white in your brooch and your fingertips begin to tingle as ordered energy flows into you.' : ''
      end
      expect(described_class.rub).to eq(:order)
    end

    it 'whispers to chaos before ANALYZE, which names what chaos gives only then' do
      on_planar = ANALYZE.map { |l| l.sub(/It is currently set to Chaos, which will use the Elemental benefit when next activated\./, 'It is currently set to Planar.') }
      on_chaos = ANALYZE.map { |l| l.sub('use the Elemental benefit', 'use the Planar benefit') }
      seen = on_planar
      allow(described_class).to receive(:analyze) { seen }
      allow(EO).to receive(:result) do |cmd, _re, **|
        sent << cmd
        seen = on_chaos if cmd == 'whisper my brooch chaos'
        cmd == 'rub my brooch' ? 'as planar energy soon replaces it' : '[Your quintuple orb brooch is now attuned to the chaos ring.]'
      end
      described_class.forget
      expect(described_class.use(:planar)).to eq(:planar)
      expect(sent).to eq(['whisper my brooch chaos', 'whisper my brooch chaos', 'rub my brooch', 'whisper my brooch chaos'])
    end

    it 'answers :no_brooch without one' do
      allow(described_class).to receive(:with_brooch).and_return(nil)
      expect(described_class.use(:spirit)).to eq(:no_brooch)
    end
  end
end

RSpec.describe 'EO.eastern_day' do
  it 'turns at midnight Eastern, standard and daylight time' do
    expect(EO.eastern_day(Time.utc(2026, 11, 13, 4, 59))).to eq('2026-11-12')
    expect(EO.eastern_day(Time.utc(2026, 11, 13, 5, 0))).to eq('2026-11-13')
    expect(EO.eastern_day(Time.utc(2026, 7, 1, 3, 59))).to eq('2026-06-30')
    expect(EO.eastern_day(Time.utc(2026, 7, 1, 4, 0))).to eq('2026-07-01')
  end

  it 'changes over with the clocks: 8 March and 1 November 2026' do
    expect(EO.eastern_day(Time.utc(2026, 3, 9, 4, 30))).to eq('2026-03-09')
    expect(EO.eastern_day(Time.utc(2026, 3, 8, 4, 30))).to eq('2026-03-07')
    expect(EO.eastern_day(Time.utc(2026, 11, 2, 4, 30))).to eq('2026-11-01')
  end
end
