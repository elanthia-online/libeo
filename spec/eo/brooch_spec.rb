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
  You may prod the brooch to turn off third-party messaging on mechanic-based verbs.
  You may whisper to the brooch, in appropriate places, to change the orb.
  [SYNTAX: WHISPER {my} BROOCH [{CHAOS} or {ELEMENT} or {ORDER} or {PLANAR} or {SPIRIT}]
  You can tell that the brooch is as light as it can get.
  The brooch is restricted to this account.
TEXT

# The game's rub and whisper lines, whole, as played (2026-01-04 log).
RUB_PLANAR = "You trace the central orb of red in your brooch and your fingertips begin to tingle as planar energy flows into you.  Within seconds, you feel Lumnis' Enlightenment course through your veins."
RUB_SPIRIT = "You trace the central orb of blue in your brooch and your fingertips begin to tingle as spiritual energy flows into you.  Within seconds, you feel Lumnis' Vigor course through your veins."
RUB_ORDER = "You trace the central orb of white in your brooch and your fingertips begin to tingle as ordered energy flows into you.  Within seconds, you feel Lumnis' Repose course through your veins."
RUB_CHAOS_PLANAR = "You trace the central orb of black in your brooch and your fingertips begin to tingle as chaotic energy flows into you.  Within seconds, you feel Lumnis' Divergence course through your veins, but it is fleeting as planar energy soon replaces it and you feel Lumnis' Enlightenment take hold."
RUB_CHAOS_SPIRIT = RUB_CHAOS_PLANAR.sub('planar energy', 'spiritual energy').sub("Lumnis' Enlightenment take hold", "Lumnis' Vigor take hold")
ATTUNED_CHAOS = '[Your quintuple orb brooch is now attuned to the chaos ring.  You can see this change in LOOK.]'
CENTERED_BLUE = 'You discreetly whisper your desire to have your brooch shift, but it is already centered on the blue orb.'
CENTERED_RED = 'You discreetly whisper your desire to have your brooch shift, but it is already centered on the red orb.'

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
      expect(rub_answer(RUB_PLANAR)).to eq(:planar)
      expect(rub_answer(RUB_SPIRIT)).to eq(:spirit)
      expect(rub_answer(RUB_ORDER)).to eq(:order)
    end

    it 'names the orb a chaos rub gave' do
      expect(rub_answer(RUB_CHAOS_PLANAR)).to eq(:planar)
      expect(rub_answer(RUB_CHAOS_SPIRIT)).to eq(:spirit)
    end

    it 'knows a spent orb' do
      expect(rub_answer('The quintuple orb brooch ebbs weakly, but nothing further happens.')).to eq(:spent)
    end
  end

  describe 'the game lines' do
    whole = {
      ATTUNED: ATTUNED_CHAOS,
      CENTERED: CENTERED_BLUE,
      UNRESPONSIVE: 'You discreetly whisper your desire to have your brooch shift, but it is unresponsive.',
      SPENT: 'The quintuple orb brooch ebbs weakly, but nothing further happens.',
      FLOWS: RUB_SPIRIT,
      REPLACED: RUB_CHAOS_PLANAR
    }

    whole.each do |name, line|
      it "#{name} matches its line whole and no more" do
        pattern = described_class.const_get(name)
        expect(line).to match(pattern)
        expect("Someone says, \"#{line}\"").not_to match(pattern)
        expect("#{line} Extra words.").not_to match(pattern)
      end
    end

    it 'reads the rub lines of a full moon night, which end with a sentence more' do
      moon = "  Liabo's full moon strengthens the power of the brooch."
      expect(rub_answer_for(RUB_SPIRIT + moon)).to eq(:spirit)
      expect(rub_answer_for(RUB_CHAOS_PLANAR + moon)).to eq(:planar)
      expect(RUB_ORDER + moon).to match(described_class::RUB)
    end

    def rub_answer_for(line)
      allow(EO).to receive(:result).and_return(line)
      described_class.rub
    end

    it 'keeps a plain rub from being taken for a chaos one, and the reverse' do
      expect(RUB_SPIRIT).not_to match(described_class::REPLACED)
      expect(RUB_CHAOS_PLANAR).not_to match(described_class::FLOWS)
    end

    it 'reads ANALYZE by its lines: the orb it is on, what chaos gives, and the day\'s uses' do
      status = described_class.parse(ANALYZE)
      expect(status.current).to eq(:chaos)
      expect(status.chaos_gives).to eq(:element)
      expect(status.uses).to eq(planar: [2, 2], spirit: [3, 5], element: [0, 0], chaos: [1, 2], order: [2, 2])
    end

    it 'ignores a use count that is not under the header, or has other words around it' do
      lines = ['Planar: 2 out of 2', '  Spiritual: 3 out of 5 today']
      expect(described_class.parse(lines).uses).to be_empty
    end
  end

  describe 'ANALYZE_START and ANALYZE_END' do
    it 'match the first line and the restriction line of the real output, and no other line' do
      expect(ANALYZE.grep(described_class::ANALYZE_START)).to eq([ANALYZE.first])
      expect(ANALYZE.grep(described_class::ANALYZE_END)).to eq([ANALYZE.last])
    end

    it 'end on a brooch bound to a character as well as to an account' do
      expect('The brooch is restricted to this character.').to match(described_class::ANALYZE_END)
    end

    it 'do not match a line that only contains the words' do
      expect('You analyze the quintuple orb brooch and nothing happens').not_to match(described_class::ANALYZE_START)
      expect('Someone says, "The brooch is restricted to this account."').not_to match(described_class::ANALYZE_END)
    end
  end

  describe '.analyze' do
    it 'captures from the first line to the restriction line, not to a prompt Lich strips' do
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
    let(:rubbed) { [RUB_SPIRIT] }

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
      rubbed.replace([RUB_CHAOS_PLANAR])
      expect(described_class.use(:planar)).to eq(:planar)
      expect(sent).to eq(['whisper my brooch chaos', 'whisper my brooch chaos', 'rub my brooch', 'whisper my brooch chaos']) # ANALYZE again after the chaos rub
    end

    it 'asks what chaos gives again only after a chaos rub, right after it' do
      text.replace([analyze_with('use the Elemental benefit' => 'use the Planar benefit', 'Chaos: 1 out of 2' => 'Chaos: 0 out of 2')])
      rubbed.replace([RUB_CHAOS_PLANAR])
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
      answers = { 'whisper my brooch spirit' => CENTERED_BLUE, 'rub my brooch' => RUB_SPIRIT }
      allow(EO).to receive(:result) { |cmd, _re, **| answers[cmd] }
      expect(described_class.use(:spirit)).to eq(:spirit)
      answers['whisper my brooch spirit'] = CENTERED_RED
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
        cmd == 'rub my brooch' ? RUB_ORDER : ''
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
        cmd == 'rub my brooch' ? RUB_CHAOS_PLANAR : ATTUNED_CHAOS
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
