# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/skinning'

RSpec.describe EO::Stow do
  let(:bag) { Struct.new(:id) }
  let(:item) { Struct.new(:type) }
  let(:list) do
    { gem: bag.new('1'), default: bag.new('2'), overflow_container_3: bag.new('5'), overflow_container: bag.new('3'), overflow_container_2: bag.new('4') }
  end

  it "routes an item to its type's bag, the default, then the overflow in number order" do
    expect(described_class.route(item.new('gem'), list).map(&:id)).to eq(%w[1 2 3 4 5])
  end

  it 'leaves a nil where a bag is not set, so its place says which' do
    list.delete(:default)
    expect(described_class.route(item.new('junk'), list).map { |b| b&.id }).to eq([nil, nil, '3', '4', '5'])
  end

  it 'lists the bags to open before looting: default, overflow as listed, each type bag once' do
    items = [item.new('gem'), item.new('junk'), item.new('gem')]
    expect(described_class.bags_for(items, list).map(&:id)).to eq(%w[2 5 3 4 1])
  end
end

RSpec.describe EO::Loot do
  include_context 'a script lending helpers'

  let(:obj) { Struct.new(:id, :name, :noun, :type, :status, keyword_init: true) }
  let(:ruby) { obj.new(id: '9', name: 'blue ruby', noun: 'ruby', type: 'gem') }

  it 'makes one whole-word pattern of a list' do
    pattern = described_class.words(['kobold', /troll king/])
    expect('a kobold shaman').to match(pattern)
    expect('a kobolds').not_to match(pattern)
    expect('the troll king').to match(pattern)
    expect('anything').not_to match(described_class.words(nil))
  end

  describe '.junk?' do
    it 'knows room features, spell leavings, disks and plain arms from loot' do
      expect(described_class.junk?(ruby)).to be(false)
      expect(described_class.junk?(obj.new(id: '1', name: 'small puddle', noun: 'puddle'))).to be(true)
      expect(described_class.junk?(obj.new(id: '1', name: 'thick mist', noun: 'mist'))).to be(true)
      expect(described_class.junk?(obj.new(id: '1', name: 'Nisugi disk', noun: 'disk'))).to be(true)
      expect(described_class.junk?(obj.new(id: '-5', name: 'bench', noun: 'bench'))).to be(true)
      expect(described_class.junk?(obj.new(id: '1', name: 'steel broadsword', noun: 'broadsword', type: 'weapon'))).to be(true)
      expect(described_class.junk?(obj.new(id: '1', name: 'glaes falchion', noun: 'falchion', type: 'weapon,uncommon'))).to be(false)
    end

    it 'counts what was learned to be unlootable or crumbly' do
      expect(described_class.junk?(ruby, unlootable: ['blue ruby'])).to be(true)
      expect(described_class.junk?(ruby, crumbly: ['blue ruby'])).to be(true)
    end

    it 'takes a kept name and the bounty heirloom for loot whatever else is so' do
      expect(described_class.junk?(ruby, keep: ['ruby'], crumbly: ['blue ruby'])).to be(false)
      expect(described_class.junk?(ruby, heirloom: /blue ruby/i, crumbly: ['blue ruby'])).to be(false)
    end
  end

  describe '.wanted?' do
    let(:none) { described_class.words([]) }

    def wanted?(thing, types, **opts) = described_class.wanted?(thing, types: types, exclude: none, level: 50, **opts)

    it 'goes by the types the character loots' do
      expect(wanted?(ruby, %w[gem])).to be(true)
      expect(wanted?(ruby, %w[skin])).to be(false)
      expect(wanted?(obj.new(name: 'odd thing', type: nil), %w[skin])).to be(true)
    end

    it 'never wants an excluded name' do
      expect(described_class.wanted?(ruby, types: %w[gem], exclude: described_class.words(['ruby']), level: 50)).to be(false)
    end

    it 'leaves a cursed gem to one who does not loot cursed, but for oblivion quartz at level 100' do
      quartz = obj.new(name: 'shard of oblivion quartz', type: 'gem,cursed')
      expect(wanted?(quartz, %w[gem])).to be(false)
      expect(described_class.wanted?(quartz, types: %w[gem], exclude: none, level: 100)).to be(true)
    end

    it 'wants the bounty heirloom whatever its type' do
      expect(wanted?(ruby, %w[skin], heirloom: /blue ruby/i)).to be(true)
    end
  end

  it 'knows the creatures whose find lands in a hand, and the brambles among them' do
    vine = obj.new(name: 'frozen vine', noun: 'vine')
    expect(described_class.in_hand?(vine)).to be(true)
    expect(described_class.bramble?(vine)).to be(true)
    golem = obj.new(name: 'stone golem', noun: 'golem')
    expect(described_class.in_hand?(golem)).to be(true)
    expect(described_class.bramble?(golem)).to be(false)
    expect(described_class.in_hand?(obj.new(name: 'kobold', noun: 'kobold'))).to be(false)
  end

  describe '.search' do
    let(:kobold) { obj.new(id: '4', name: 'kobold', noun: 'kobold', status: 'dead') }
    let(:sigil) { { affordable: true, active: false, casts: 0 } }

    before do
      state = sigil
      stub_const('Spell', Class.new do
        define_singleton_method(:[]) do |_name|
          Class.new do
            define_method(:affordable?) { state[:affordable] }
            define_method(:active?) { state[:active] }
            define_method(:cast) { state[:casts] += 1 }
          end.new
        end
      end)
      stub_const('GameObj', Struct.new(:id, :noun, :name))
      described_class.define_singleton_method(:waitrt?) { nil }
    end

    after { described_class.singleton_class.remove_method(:waitrt?) }

    it 'loots once when the game answers the search' do
      answers['loot #4'] = ['You search the kobold.']
      described_class.search(kobold)
      expect(sent).to eq(['loot #4'])
    end

    it 'hands over each find left at the feet' do
      answers['loot #4'] = ['You search the kobold.', 'Among the remains, you find a <a exist="77" noun="gem">blue gem</a>, which falls alongside your feet.']
      found = []
      described_class.search(kobold, on_find: ->(item) { found << item.to_a })
      expect(found).to eq([['77', 'gem', 'blue gem']])
    end

    it 'casts Sigil of Determination and tries again when too hurt, if told to' do
      answers['loot #4'] = [['You are not in any condition to search.'], ['You search the kobold.']]
      described_class.search(kobold, sigil: true)
      expect(sigil[:casts]).to eq(1)
      expect(sent.size).to eq(2)
    end

    it 'stops at "not in any condition" without the sigil' do
      answers['loot #4'] = ['You are not in any condition to search.']
      described_class.search(kobold)
      expect(sent.size).to eq(1)
    end

    it 'tries three times on no answer it knows' do
      described_class.search(kobold)
      expect(sent.size).to eq(3)
    end
  end
end

RSpec.describe EO::Skinning do
  include_context 'a script lending helpers'

  let(:obj) { Struct.new(:id, :name, :type, keyword_init: true) }
  let(:none) { EO::Loot.words([]) }

  def skip?(thing, unskinnable: [], exclude: []) = described_class.skip?(thing, unskinnable: unskinnable, exclude: exclude, never: none)

  it 'leaves bandits, the ghostly, the learned and the excluded' do
    expect(skip?(obj.new(name: 'kobold'))).to be(false)
    expect(skip?(obj.new(name: 'bandit', type: 'bandit'))).to be(true)
    expect(skip?(obj.new(name: 'ghostly warrior'))).to be(true)
    expect(skip?(obj.new(name: 'kobold'), unskinnable: ['kobold'])).to be(true)
    expect(skip?(obj.new(name: 'kobold'), exclude: ['kob'])).to be(true)
    expect(sent).to be_empty
  end

  it 'skins a rotting chimera learned as unskinnable when it shows its scorpion tail' do
    chimera = obj.new(name: 'rotting chimera')
    answers['describe chimera'] = [['The twisted and confused form', 'A huge scorpion tail rises high from the rear'], ['The twisted and confused form']]
    expect(skip?(chimera, unskinnable: ['rotting chimera'])).to be(false)
    expect(skip?(chimera, unskinnable: ['rotting chimera'])).to be(true)
  end

  it "keeps to a bounty's creature, and splits the dead by the tool they take" do
    dead = [obj.new(name: 'kobold'), obj.new(name: 'stone mastiff'), obj.new(name: 'big kobold')]
    expect(described_class.for_bounty(dead, 'Kobold').map(&:name)).to eq(['kobold', 'big kobold'])
    edged, blunt = described_class.by_tool(dead)
    expect(edged.map(&:name)).to eq(['kobold', 'big kobold'])
    expect(blunt.map(&:name)).to eq(['stone mastiff'])
  end

  describe '.skin' do
    let(:fputs) { [] }

    before do
      log = fputs
      reply = replies = []
      @replies = replies
      stub_const('GameObj', Class.new { define_singleton_method(:left_hand) { Struct.new(:id).new('66') } })
      described_class.define_singleton_method(:dothistimeout) { |cmd, *_| log << cmd && reply.shift }
      described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    end

    after { %i[dothistimeout fput].each { |m| described_class.singleton_class.remove_method(m) } }

    it 'skins with the hand holding the tool' do
      @replies << 'You skinned the kobold, yielding a kobold skin.'
      expect(described_class.skin(obj.new(id: '4'), 'left')).to eq(:done)
      expect(fputs).to eq(['skin #4 left'])
    end

    it 'tells a creature that is not one to skin' do
      @replies.push('You cannot skin the kobold.', "The Krolvin Captain's skin has been ruined with alchemical components.")
      expect(described_class.skin(obj.new(id: '4'), 'right')).to eq(:cannot)
      expect(described_class.skin(obj.new(id: '5'), 'right')).to eq(:cannot)
    end

    it 'stows the gem a skinning broke out, from the left hand' do
      @replies << 'You break through the crust of the krynch and withdraw a blue gem!'
      expect(described_class.skin(obj.new(id: '4'), 'right')).to eq(:done)
      expect(fputs).to eq(['skin #4 right', 'stow gem #66'])
    end
  end

  describe '.stand_up' do
    it 'stands on the offensive when nothing is there to fight, and goes back to the stance before' do
      up = [false]
      stances = []
      stub_const('Stance', Class.new { define_singleton_method(:current) { 'defensive' } })
      stub_const('GameObj', Class.new { define_singleton_method(:targets) { [] } })
      described_class.define_singleton_method(:standing?) { up.first }
      described_class.define_singleton_method(:dothistimeout) { |*_| up[0] = true }
      described_class.stand_up(stance: ->(name) { stances << name })
      expect(stances).to eq(%w[offensive defensive])
      described_class.stand_up(stance: ->(name) { stances << name })
      expect(stances.size).to eq(2)
    ensure
      %i[standing? dothistimeout].each { |m| described_class.singleton_class.remove_method(m) }
    end
  end
end
