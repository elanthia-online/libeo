# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/casting'
require_relative '../../scripts/eo/wander'

RSpec.describe EO::Casting do
  # A spell as Lich's Spell answers: what it costs, whether it can be
  # afforded, and what a cast comes back with.
  let(:spell_type) do
    Struct.new(:num, :cost, :affordable, :active, :answers, :casts, :circle, keyword_init: true) do
      def mana_cost(multicast: 1) = cost * multicast
      def affordable?(**) = affordable.respond_to?(:call) ? affordable.call : affordable
      def active? = active

      def cast(*args)
        casts << args
        answers.shift
      end
    end
  end
  let(:char) { { mana: 100, stamina: 100 } }
  let(:echoed) { [] }
  let(:fputs) { [] }

  def spell(**opts) = spell_type.new(num: 401, cost: 10, affordable: true, active: false, answers: [], casts: [], **opts)

  def resources(**opts) = described_class::Resources.new(reserve: 0, source: nil, bail: false, wander_to_wrack: false, **opts)

  before do
    state = char
    stub_const('Char', Class.new do
      define_singleton_method(:mana) { state[:mana] }
      define_singleton_method(:stamina) { state[:stamina] }
    end)
    said = echoed
    sent = fputs
    described_class.define_singleton_method(:echo) { |text| said << text }
    described_class.define_singleton_method(:fput) { |cmd| sent << cmd }
    described_class.define_singleton_method(:checkprep) { 'None' }
    described_class.define_singleton_method(:wait_until) { |&block| 100.times { break if block.call } }
    %i[waitrt? waitcastrt?].each { |m| described_class.define_singleton_method(m) { nil } }
    allow(described_class).to receive(:sleep)
  end

  after { %i[echo fput checkprep wait_until waitrt? waitcastrt?].each { |m| described_class.singleton_class.remove_method(m) } }

  describe '.max_multicast' do
    def ranks(prof, circle, emc: 0, smc: 0, mmc: 0)
      stub_const('Stats', Class.new { define_singleton_method(:prof) { prof } })
      stub_const('Skills', Class.new do
        define_singleton_method(:emc) { emc }
        define_singleton_method(:smc) { smc }
        define_singleton_method(:mmc) { mmc }
      end)
      described_class.max_multicast(spell(circle: circle))
    end

    it 'goes by the mana control the profession uses for the circle' do
      expect(ranks('Wizard', 4, emc: 50)).to eq(3)
      expect(ranks('Cleric', 3, smc: 24)).to eq(1)
      expect(ranks('Empath', 11, smc: 50, mmc: 100)).to eq(6)
      expect(ranks('Sorcerer', 7, emc: 100, smc: 50)).to eq(6)
      expect(ranks('Warrior', 9, emc: 100)).to eq(1)
    end
  end

  describe '.cast' do
    it 'casts at oneself plain, with a count, or with an argument that may be nil' do
      plain = spell
      described_class.cast(plain)
      described_class.cast(plain, multicast: 3)
      described_class.cast(plain, multicast: 3, argument: 'lute')
      described_class.cast(plain, argument: nil)
      expect(plain.casts).to eq([[], ['3'], ['lute'], [nil]])
    end

    it 'casts at a target, with the count after the name' do
      aimed = spell
      described_class.cast(aimed, target: 'Dicate')
      described_class.cast(aimed, target: 'Dicate', multicast: 2)
      expect(aimed.casts).to eq([['at Dicate'], ['at Dicate 2']])
    end

    it 'says what the answer means' do
      answers = ['Be at peace my child, there is no need for spells of war in here.', 'Cast at what?',
                 '[Spell Hindrance for full plate is 12%, you rolled 5]', 'You gesture.', false]
      outcomes = answers.map { |answer| described_class.cast(spell(answers: [answer])) }
      expect(outcomes).to eq(%i[refused_here bad_target hindered success success])
    end
  end

  describe '.ready' do
    it 'is ready with the mana for the casts and the reserve, or for a spell that costs none' do
      expect(described_class.ready(spell, 3, resources(reserve: 70))).to eq(:ready)
      expect(described_class.ready(spell(cost: 0, affordable: false), 1, resources)).to eq(:ready)
      expect(echoed).to be_empty
    end

    it 'says it is waiting, and bails when told to' do
      expect(described_class.ready(spell, 3, resources(reserve: 80, bail: true))).to eq(:bail)
      expect(echoed).to eq(['waiting for mana...'])
    end

    it 'waits for the mana otherwise' do
      allow(described_class).to receive(:wait_until) { char[:mana] = 200 }
      expect(described_class.ready(spell, 3, resources(reserve: 80))).to eq(:ready)
    end

    it 'makes mana with Sigil of Power while it can be afforded' do
      sigil = spell(num: 9718)
      stub_const('Spell', Class.new { define_singleton_method(:[]) { |_num| sigil } })
      allow(described_class).to receive(:sleep) { char[:mana] += 20 }
      expect(described_class.ready(spell, 3, resources(reserve: 100, source: :power))).to eq(:ready)
      expect(sigil.casts.size).to eq(2)
    end

    it 'stops using Symbol of Mana when the favor has run out' do
      symbol = spell(num: 9813, answers: ['You strain to perform the symbol, but lack the favor.'])
      stub_const('Spell', Class.new { define_singleton_method(:[]) { |_num| symbol } })
      stub_const('Effects::Cooldowns', Class.new { define_singleton_method(:active?) { |_name| false } })
      expect(described_class.ready(spell, 3, resources(reserve: 100, source: :voln))).to eq(:no_favor)
    end

    context 'with someone watching who is not of the Council' do
      let(:sign) { spell(num: 9918) }
      let(:rooms) { [] }

      before do
        the_sign = sign
        seen = rooms
        stub_const('Spell', Class.new { define_singleton_method(:[]) { |_num| the_sign } })
        stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:id, :tags).new(seen.size, []) } })
        stub_const('Script', Class.new { define_singleton_method(:run) { |*args| seen << args } })
        %i[invisible? hidden?].each { |m| described_class.define_singleton_method(m) { false } }
        described_class.define_singleton_method(:checkpcs) { ['Someone'] }
        allow(described_class).to receive(:safe_to_wrack?).and_return(false)
        allow(described_class).to receive(:wander_step) { |visited| seen << visited }
        char[:mana] = 0
      end

      after { %i[invisible? hidden? checkpcs].each { |m| described_class.singleton_class.remove_method(m) } }

      it 'does not wrack, and waits for the mana or bails' do
        expect(described_class.ready(spell, 3, resources(source: :wracking, bail: true))).to eq(:bail)
        allow(described_class).to receive(:wait_until) { char[:mana] = 100 }
        expect(described_class.ready(spell, 3, resources(source: :wracking))).to eq(:ready)
        expect(sign.casts).to be_empty
        expect(echoed).to eq(['waiting for mana: nowhere to wrack unseen...'] * 2)
      end

      it 'does not wrack after walking twenty rooms and finding nowhere, and comes back' do
        expect(described_class.ready(spell, 3, resources(source: :wracking, bail: true, wander_to_wrack: true))).to eq(:bail)
        expect(sign.casts).to be_empty
        expect(rooms.size).to eq(21)
        expect(rooms.last).to eq(['go2', '0 --disable-confirm', { quiet: true }])
      end
    end

    it 'wracks when alone, and bails when the sign cannot be afforded' do
      sign = spell(num: 9918)
      stub_const('Spell', Class.new { define_singleton_method(:[]) { |_num| sign } })
      stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:tags).new([]) } })
      %i[invisible? hidden? checkpcs].each { |m| described_class.define_singleton_method(m) { nil } }
      sign.answers << 'ok'
      allow(sign).to(receive(:cast).and_wrap_original { |original, *args| (char[:mana] += 50) && original.call(*args) })
      expect(described_class.ready(spell, 3, resources(reserve: 100, source: :wracking))).to eq(:ready)

      char[:mana] = 0
      sign.affordable = false
      expect(described_class.ready(spell, 3, resources(source: :wracking, bail: true))).to eq(:bail)
      expect(echoed.last).to eq('waiting for mana or spirit...')
    ensure
      %i[invisible? hidden? checkpcs].each { |m| described_class.singleton_class.remove_method(m) }
    end
  end

  describe '.ready_stamina' do
    it 'needs twice the mana cost in stamina, and the reserve' do
      expect(described_class.ready_stamina(spell, 3, resources(reserve: 40))).to eq(:ready)
      expect(described_class.ready_stamina(spell, 3, resources(reserve: 50, bail: true))).to eq(:bail)
      expect(echoed).to eq(['waiting for stamina...'])
    end
  end

  describe '.wander_step' do
    it 'steps to a room not yet visited, then to the one visited longest ago' do
      moves = []
      room = Struct.new(:wayto, :timeto).new({ '2' => 'north', '3' => 'east' }, { '2' => 0.2, '3' => 0.2 })
      stub_const('Room', Class.new { define_singleton_method(:current) { room } })
      described_class.define_singleton_method(:move) { |way| moves << way }
      visited = ['2']
      described_class.wander_step(visited)
      described_class.wander_step(visited)
      expect(moves).to eq(%w[east north])
      expect(visited).to eq(%w[3 2])
    ensure
      described_class.singleton_class.remove_method(:move)
    end
  end

  describe '.active_on' do
    before do
      stub_const('Spell', Class.new do
        define_singleton_method(:list) { [Struct.new(:name, :num).new('Spirit Warding I', 101), Struct.new(:name, :num).new('Mage Armor', 520)] }
      end)
    end

    def spell_active(lines)
      stub_const('Lich::Util', Class.new { define_singleton_method(:quiet_command_xml) { |*_| lines } })
      described_class.active_on('Dicate')
    end

    it "reads each spell's minutes left, and one that does not end as 599" do
      info = spell_active(['Dicate currently has the following active effects:', '  Spirit Warding I ........ 1:30:30', '  Mage Armor - Fire ....... Indefinite'])
      expect(info).to eq('101' => 90.5, '520' => 599.0, 'sharing' => true)
    end

    it 'has only that they do not share for one who does not' do
      expect(spell_active(['Dicate has spell sharing disabled.'])).to eq('sharing' => false)
    end
  end

  describe 'manna bread' do
    let(:thing) { Struct.new(:id) }
    let(:hands) { { right: thing.new(nil), left: thing.new(nil) } }
    let(:manna) { [0] }

    before do
      held = hands
      left = manna
      stub_const('GameObj', Class.new do
        define_singleton_method(:right_hand) { held[:right] }
        define_singleton_method(:left_hand) { held[:left] }
      end)
      stub_const('Effects::Spells', Class.new { define_singleton_method(:time_left) { |_name| left.first } })
    end

    it 'takes whatever new item lands in a hand for the bread' do
      hands[:right] = thing.new('5')
      expect(described_class.new_in_hand(['5', nil])).to be_nil
      hands[:left] = thing.new('6')
      expect(described_class.new_in_hand(['5', nil]).id).to eq('6')
    end

    it 'gobbles while the bread is in hand, three times at most' do
      hands[:left] = thing.new('6')
      described_class.gobble(hands[:left])
      expect(fputs).to eq(['gobble #6'] * 3)
    end

    it 'only waits for Manna when there is no bread' do
      described_class.gobble(nil)
      expect(fputs).to be_empty
      expect(described_class).to have_received(:sleep).with(0.1).exactly(20).times
    end
  end
end
