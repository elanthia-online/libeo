# frozen_string_literal: true

require 'tmpdir'
require_relative 'eo_helper'
require_relative '../../scripts/eo/settings'
require_relative '../../scripts/eo/carry'

# Nisugi's measurements on 2026-11-12: Half-Elf, base STR 100 / CON 97,
# enhanced STR 115 (151 under Assume Lion), 509 and 606 up, Physical Fitness
# bonus 302, the SimuCoin reduction on, 90 lbs of gear the game counts
# (98 in the feed, less 8 lbs of standard robes). Encumbrance turned 0 -> 10
# between 37,311 and 37,312 silver, and at 44,340 silver under Assume Lion.
RSpec.describe EO::Carry do
  let(:body) { described_class.body_weight(race: 'Half-Elf', str: 100, con: 97) }
  let(:extras) { described_class.extras(pf_bonus: 302, porter: 0, simu: true) }

  around do |example|
    Dir.mktmpdir { |dir| (@dir = dir) && example.run }
  end

  before do
    stub_const('DATA_DIR', @dir)
    stub_const('XMLData', Struct.new(:game).new('GSIV'))
    stub_const('Char', Struct.new(:name).new('Nisugi'))
    EO::Settings.instance_variable_set(:@held, {})
  end

  it 'weighs the body from race and base STR and CON, each taken even' do
    expect(body).to be_within(0.1).of(243.7)
    expect(described_class.body_weight(race: 'Giantman', str: 100, con: 100)).to eq(360.0)
    expect(described_class.body_weight(race: 'Unknown', str: 100, con: 100)).to be_nil
  end

  it "counts a spell's Strength bonus twice into STR, and truncates the factor" do
    expect(described_class.effective_str(enhanced: 115, spell_bonus: 25)).to eq(165)
    expect(described_class.base_capacity(165, body)).to be_within(0.1).of(176.7)
    expect(described_class.base_capacity(201, body)).to be_within(0.1).of(220.5)
  end

  it 'misses the measured capacity by the same amount with and without Assume Lion' do
    plain = 90 + (37_311.5 / 160)
    lion = 90 + (44_340 / 160.0)
    gap_plain = plain - (described_class.base_capacity(165, body) + extras)
    gap_lion = lion - (described_class.base_capacity(201, body) + extras)
    expect(gap_plain).to be_within(0.5).of(16.3)
    expect(gap_lion).to be_within(1.5).of(gap_plain)
  end

  it 'learns the correction from the bands either side of the edge' do
    model = described_class.base_capacity(165, body) + extras
    described_class.learn(0, carried: 90 + (37_311 / 160.0), model: model, body: body)
    expect(described_class.correction).to be_within(0.1).of(16.3)
    described_class.learn(10, carried: 90 + (37_312 / 160.0), model: model, body: body)
    expect(described_class.correction).to be_within(0.05).of(16.3)
  end

  it 'starts over when a reading fits nothing learned' do
    described_class.learn(0, carried: 300, model: 280, body: 240)
    described_class.learn(10, carried: 301, model: 280, body: 240)
    expect(described_class.correction).to be_within(0.6).of(20.5)
    described_class.learn(20, carried: 400, model: 280, body: 240)
    expect(described_class.correction).to be_within(0.1).of(84.0)
  end

  it 'keeps the formula while only unencumbered readings are known' do
    described_class.learn(0, carried: 100, model: 180, body: 240)
    expect(described_class.correction).to eq(0.0)
    described_class.learn(0, carried: 190, model: 180, body: 240)
    expect(described_class.correction).to eq(10.0)
  end

  it 'takes the bands past 50 as the game steps them: 65, 80, 100' do
    # 52% over reads 65: the band runs from 50, not from 55
    described_class.learn(65, carried: 180 + 20 + (0.52 * 240), model: 180, body: 240)
    low, high = described_class.state.values_at(:low, :high)
    expect(low).to be < 20
    expect(high).to be > 20
    expect(high - low).to be_within(0.01).of(0.15 * 240)
  end

  it 'takes 100 as anything past 80, Overloaded included' do
    described_class.learn(100, carried: 180 + 20 + (1.5 * 240), model: 180, body: 240)
    low, high = described_class.state.values_at(:low, :high)
    expect(low).to be_nil
    expect(high).to be > 20
  end

  it 'learns nothing from a value the bar does not take' do
    described_class.learn(55, carried: 400, model: 180, body: 240)
    expect(described_class.state.values_at(:low, :high)).to eq([nil, nil])
  end

  it 'gives the encumbrance percent of body weight past capacity' do
    expect(described_class.percent(400, capacity: 331.2, body: 244)).to be_within(0.1).of(28.2)
    expect(described_class.percent(300, capacity: 331.2, body: 244)).to eq(0)
  end

  describe '.carried' do
    let(:item) do
      Struct.new(:weight, :type, :noun, :relation, :in_encum, :contents, keyword_init: true) do
        def container? = !contents.empty?
      end
    end

    it 'leaves standard robes out, counts a gem shown as 0, and adds silver' do
      robes = item.new(weight: 8, noun: 'robes', relation: 'worn', contents: [])
      gem = item.new(weight: 0, type: 'gem', contents: [])
      satchel = item.new(weight: 2, noun: 'satchel', relation: 'worn', contents: [gem] * 10)
      cloak = item.new(weight: 4, noun: 'cloak', relation: 'worn', in_encum: 15, contents: [gem])
      snapshot = Struct.new(:worn, :right_hand, :left_hand).new([robes, satchel, cloak], nil, nil)
      allow(described_class).to receive(:armor_stats) { |i| i.noun == 'robes' ? { base_weight: 8 } : nil }

      expect(described_class.carried(snapshot, silver: 1600)).to be_within(0.01).of(2 + 1 + 4 + 15 + 10)
    end

    it 'counts lightened or heavier robes once, through the adjustment' do
      allow(described_class).to receive(:armor_stats) { |i| i.noun == 'robes' ? { base_weight: 8 } : nil }
      net = lambda do |pounds|
        robes = item.new(weight: pounds, noun: 'robes', relation: 'worn', contents: [])
        snapshot = Struct.new(:worn, :right_hand, :left_hand).new([robes], nil, nil)
        described_class.armor_adjustment(snapshot, race: 'Human') - described_class.carried(snapshot, silver: 0)
      end

      expect(net.call(8)).to eq(0)
      expect(net.call(7)).to eq(1)
      expect(net.call(9)).to eq(-1)
    end
  end

  describe '.armor_stats' do
    let(:worn) { Struct.new(:name, :noun, :relation, :id, :weight) }
    let(:names) do
      { 'full plate'    => [{ armor_sub_group: 20, base_weight: 75 }],
        'plate'         => [{ armor_sub_group: 19, base_weight: 50 }, { armor_sub_group: 20, base_weight: 75 }],
        'leather tunic' => [{ armor_sub_group: 5, base_weight: 10 }],
        'tunic'         => [{ armor_sub_group: 2, base_weight: 8 }, { armor_sub_group: 9, base_weight: 16 }],
        'chain'         => [{ armor_sub_group: 13, base_weight: 25 }, { armor_sub_group: 14, base_weight: 25 }],
        'outfit'        => [{ armor_sub_group: 1, base_weight: 0 }] }
    end

    before do
      table = names
      standard = { 2 => 8, 10 => 17, 17 => 23, 20 => 75 }
      stub_const('Lich::Gemstone::Armaments::ArmorStats', Module.new do
        define_singleton_method(:find_all) { |name| table[name] }
        define_singleton_method(:find_by_asg) { |asg| standard[asg] && { base_weight: standard[asg] } }
      end)
    end

    it "reads the sub-group from INSPECT's armor group and coverage" do
      expect(described_class.inspected_weight('cloth', 'the torso, arms, legs, neck, and head')).to eq(8)
      expect(described_class.inspected_weight('scale', 'the torso and arms')).to eq(17)
      expect(described_class.inspected_weight('plate', 'the torso only')).to eq(23)
      expect(described_class.inspected_weight('plate', 'the torso, arms, legs, neck, and head')).to eq(75)
      expect(described_class.inspected_weight('cloth', 'the torso only')).to be_nil
    end

    describe 'with two tunics worn, one of them the robes' do
      let(:robes) { worn.new('a dark green elesine tunic', 'tunic', 'worn', '11', 7) }
      let(:shirt) { worn.new('a linen tunic', 'tunic', 'worn', '12', 2) }
      let(:snapshot) { Struct.new(:worn).new([shirt, robes]) }
      let(:asked) { [] }
      let(:listing) do
        ['You are currently wearing:', '', 'On your head:', '    a <a exist="10" noun="cap">round otter fur cap</a>', '',
         'Over your chest:', '    a <a exist="11" noun="tunic">dark green elesine tunic</a>', '',
         'Slipped into, on your chest:', '    a <a exist="12" noun="tunic">linen tunic</a>', '', '(3 items displayed)']
      end
      let(:inspection) do
        ['You carefully inspect your tunic.',
         'Your careful inspection of a tunic allows you to conclude that it is cloth armor that covers the torso, arms, legs, neck, and head.']
      end

      before do
        log = asked
        answers = { 'inventory location' => listing, 'inspect #11' => inspection }
        allow(EO).to receive(:command) do |command, *|
          log << command
          answers[command] || []
        end
      end

      it 'takes what is worn over the chest for the armor, and asks INSPECT which it is' do
        described_class.identify_armor(snapshot)
        expect(asked).to eq(['inventory location', 'inspect #11'])
        expect(described_class.armor_stats(robes)).to eq(base_weight: 8)
        expect(described_class.armor_stats(shirt)).to be_nil
      end

      it 'asks once while the same things are worn' do
        2.times { described_class.identify_armor(snapshot) }
        expect(asked.size).to eq(2)
      end

      it 'asks again when what is worn changes, and skips INSPECT for a name of one weight' do
        described_class.identify_armor(snapshot)
        plate = worn.new('some full plate', 'plate', 'worn', '13', 75)
        allow(EO).to receive(:command).and_return(['You are currently wearing:', 'Over your chest:', '    <a exist="13" noun="plate">some full plate</a>'])
        described_class.identify_armor(Struct.new(:worn).new([shirt, plate]))
        expect(EO).to have_received(:command).exactly(3).times # two before, then the listing alone
        expect(described_class.armor_stats(plate)).to eq(base_weight: 75)
        expect(described_class.state[:armor].keys).to eq(['13'])
      end

      it 'keeps to the name when INVENTORY LOCATION gives no answer' do
        allow(EO).to receive(:command).and_return([])
        described_class.identify_armor(snapshot)
        expect(described_class.state[:armor]).to be_nil
        expect(described_class.armor_stats(robes)).to eq(base_weight: nil)
      end

      it 'takes the armor as standard and asks again when INSPECT gives no answer' do
        allow(EO).to receive(:command) { |command, *| command == 'inventory location' ? listing : [] }
        described_class.identify_armor(snapshot)
        expect(described_class.armor_stats(robes)).to eq(base_weight: nil)
        expect(described_class.armor_stats(shirt)).to be_nil
        expect(described_class.state[:armor_seen]).to be_nil
      end
    end

    it 'goes by the longest armor name the item ends with, not the bare noun' do
      expect(described_class.armor_stats(worn.new('some blackened full plate', 'plate', 'worn'))).to eq(base_weight: 75)
      expect(described_class.armor_stats(worn.new('a supple leather tunic', 'tunic', 'worn'))).to eq(base_weight: 10)
    end

    it 'has no standard weight for a name that fits sub-groups of different weights' do
      expect(described_class.armor_stats(worn.new('a dented plate', 'plate', 'worn'))).to eq(base_weight: nil)
      expect(described_class.armor_stats(worn.new('a linen tunic', 'tunic', 'worn'))).to eq(base_weight: nil)
      expect(described_class.armor_stats(worn.new('some rusty chain', 'chain', 'worn'))).to eq(base_weight: 25)
    end

    it 'takes only worn armor, and not normal clothing' do
      expect(described_class.armor_stats(worn.new('some full plate', 'plate', 'in'))).to be_nil
      expect(described_class.armor_stats(worn.new('a silk outfit', 'outfit', 'worn'))).to be_nil
      expect(described_class.armor_stats(worn.new('a leather backpack', 'backpack', 'worn'))).to be_nil
    end
  end

  it 'reads the SimuCoin reduction once and keeps it until it runs out' do
    allow(EO).to receive(:command).and_return(['Encumbrance Reduction                             Until Sat Dec  5 01:44:20 ET 2026'])
    now = Time.new(2026, 11, 13)
    expect(described_class.simu_reduction?(now: now)).to be(true)
    expect(described_class.simu_reduction?(now: now)).to be(true)
    expect(EO).to have_received(:command).once
    expect(described_class.simu_reduction?(now: Time.new(2026, 12, 6))).to be(false)
  end

  it 'asks once a day of a character whose reduction has expired' do
    allow(EO).to receive(:command).and_return(['Encumbrance Reduction                             Expired on Sun Jan 11 13:00:09 ET 2026'])
    now = Time.new(2026, 11, 13)
    expect(described_class.simu_reduction?(now: now)).to be(false)
    expect(described_class.simu_reduction?(now: now + 3600)).to be(false)
    expect(EO).to have_received(:command).once
    described_class.simu_reduction?(now: now + (25 * 3600))
    expect(EO).to have_received(:command).twice
  end

  it 'does not take no answer from SIMU DUR for no reduction' do
    allow(EO).to receive(:command).and_return([])
    now = Time.new(2026, 11, 13)
    expect(described_class.simu_reduction?(now: now)).to be(false)
    expect(described_class.state[:simu_checked]).to be_nil
  end

  it "gives the disk's item limit, half the lore without 511 known" do
    expect(described_class.disk_limit(ranks: 0, native: true)).to eq(8)
    expect(described_class.disk_limit(ranks: 21, native: true)).to eq(10)
    expect(described_class.disk_limit(ranks: 19, native: false)).to eq(8)
    expect(described_class.disk_limit(ranks: 20, native: false)).to eq(9)
    expect(described_class.disk_limit(ranks: 42, native: false)).to eq(10)
  end
end
