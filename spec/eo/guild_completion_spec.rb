# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/guild/completion'

RSpec.describe EO::Guild::Completion do
  include_context 'a script lending helpers'

  describe '.rule' do
    def rule(bounty = 'You have been tasked to suppress kobold activity.', **opts)
      described_class.rule(bounty, exp_pause: false, keep_hunting: false, **opts)
    end

    it 'stops on a task done with the mind full, a bandit task done, or a new task on offer' do
      text = rule
      expect(text).to include('@CORRECT_PERCENT_MIND >= 100)')
      expect(text).to include('&& $bigshot_bandits)')
      expect(text).to include("!Effects::Cooldowns.to_h.include?('Next Bounty')")
    end

    it "goes by the hunting script's own limit for the mind when pausing on experience" do
      expect(described_class.rule('x', exp_pause: true, keep_hunting: true)).to include("@CORRECT_PERCENT_MIND >= UserVars.op['fried'].to_i)")
    end

    it 'does not stop while the mind is saturated when hunting on' do
      expect(described_class.rule('x', exp_pause: false, keep_hunting: true)).to include("checkmind != 'saturated'")
    end

    it 'adds the child found for a rescue' do
      text = rule('A local divinist has had visions of the child fleeing from a kobold.')
      expect(text).to include('You have made contact with the child', '/\bchild\b/')
    end

    it 'counts a bundle and the loose skins together, in one test' do
      text = rule('You have been tasked to retrieve 5 kobold skins of at least fair quality.', bundle_skin: 'kobold skin', skin: 'kobold skin')
      expect(text.scan('EBounty.data.remaining_skins').size).to eq(1)
      expect(text).to include('elsif k.name =~ /kobold skin/i && !EBounty.data.skin.to_s.empty?; count += 1;end;')
    end

    it 'gives a rule that counts four in a bundle and one loose as five' do
      text = rule('You have been tasked to retrieve 5 kobold skins of at least fair quality.', bundle_skin: 'kobold skin', skin: 'kobold skin')
      clause = text[/ \|\| (!!\(count = 0;.*)\z/m, 1]
      item = Struct.new(:id, :name)
      bags = [Struct.new(:contents).new([item.new('2', 'bundle of kobold skin'), item.new('1', 'a kobold skin')])]
      data = Struct.new(:containers, :bundle_skin, :skin, :remaining_skins, :complete_mind).new(bags, 'kobold skin', 'kobold skin', 5, 0)
      stub_const('EBounty', Class.new { define_singleton_method(:data) { data } })
      stub_const('Lich::Util', Class.new do
        define_singleton_method(:quiet_command_xml) { |_cmd, _pattern| ['You glance through the bundle and count a total of 4 <a exist="2">skins</a>.'] }
      end)
      runner = Object.new
      runner.instance_variable_set(:@CORRECT_PERCENT_MIND, 100)
      runner.define_singleton_method(:hidden?) { false }
      expect(runner.instance_eval(clause)).to be(true)
      data.remaining_skins = 6
      expect(runner.instance_eval(clause)).to be(false)
    end

    it 'adds the skins counted, in a bundle or loose, for a skin task' do
      text = rule('You have been tasked to retrieve 5 kobold skins of at least fair quality.', bundle_skin: 'kobold skin', skin: 'kobold skin')
      expect(text).to include('/bundle of kobold skin/', 'k.name =~ /kobold skin/i', 'count a total of (\d+) <a exist')
    end

    it 'adds the gems counted for a gem task' do
      text = rule('The gem dealer in town has received orders.', gem: ' blue ruby ')
      expect(text).to include('v.name =~ /blue ruby$/i')
    end

    it 'is Ruby a hunting script can evaluate' do
      text = rule('The gem dealer in town has received orders.', gem: 'ruby')
      expect { RubyVM::InstructionSequence.compile(text) }.not_to raise_error
    end
  end

  it 'reads what a skin task asks for, and names the skin as items carry it' do
    expect(described_class.skin_wanted('You have been tasked to retrieve 5 kobold skins of at least fair quality.')).to eq([5, 'kobold skin'])
    expect(described_class.skin_wanted('You are not currently assigned a task.')).to be_nil
    expect(described_class.skin_name(' Wolf Teeth ')).to eq('wolf tooth')
    expect(described_class.skin_name('boar hooves')).to eq('boar hoof')
    expect('thick kobold skin'[described_class::BUNDLE_WORDS]).to eq('kobold skin')
  end

  describe 'counting what is held' do
    let(:item) { Struct.new(:id, :name) }
    let(:bag) { Struct.new(:contents) }
    let(:opened) { [] }

    it 'counts skins loose and in a bundle, which it measures' do
      bags = [bag.new([item.new('1', 'kobold skin'), item.new('2', 'bundle of kobold skin')]), bag.new([item.new('3', 'ruby')])]
      answers['measure #2'] = ['You glance through the bundle and count a total of 4 <a exist="2">skins</a>.']
      expect(described_class.skins_held(bags, 'kobold skin', 'kobold skin', open: ->(b) { opened << b })).to eq(5)
      expect(opened.size).to eq(2)
    end

    it 'counts gems by how their names end' do
      bags = [bag.new([item.new('1', 'blue ruby'), item.new('2', 'ruby dust'), item.new('3', 'star ruby')])]
      expect(described_class.gems_held(bags, 'ruby', open: ->(_b) {})).to eq(2)
    end
  end

  it 'guesses the minutes until what is over the limit is absorbed' do
    stub_const('Lich::Gemstone::Experience', Class.new do
      define_singleton_method(:fxp_current) { 2200 }
      define_singleton_method(:fxp_max) { 1800 }
    end)
    stub_const('Stats', Class.new { define_singleton_method(:enhanced_log) { [100, 25] } })
    # 25 + 5 + 2 + 10 + 1 = 43 a pulse; 400 over is 9 pulses, two minutes each
    expect(described_class.minutes_to_absorb).to eq(18)
  end
end
