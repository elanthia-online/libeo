# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/herbs/table'
require_relative '../../scripts/eo/herbs/injuries'
require_relative '../../scripts/eo/herbs/sack'
require_relative '../../scripts/eo/herbs/heal'
require_relative '../../scripts/eo/herbs/shop'

RSpec.describe EO::Herbs::Heal do
  include_context 'a script lending helpers'

  let(:obj) { Struct.new(:id, :name, :noun) }
  let(:leaf) { obj.new('7', 'some acantha leaf', 'leaf') }
  let(:tincture) { obj.new('8', 'tincture of acantha', 'tincture') }
  let(:yaba) { obj.new('9', 'tincture of yabathilium', 'tincture') }
  let(:contents) { { all: [leaf, tincture, yaba], edible: [leaf], drinkable: [tincture, yaba] } }

  it 'knows what a herb treats by its name or short name' do
    expect(described_class.treats?(leaf, 'blood')).to be(true)
    expect(described_class.treats?(leaf, 'poison')).to be(false)
  end

  it 'takes something eaten first, or something drunk when potions are preferred' do
    expect(described_class.find(contents, 'blood')).to equal(leaf)
    expect(described_class.find(contents, 'blood', use_potions: true)).to equal(tincture)
  end

  it 'takes yabathilium for blood when that is preferred, and anything when the form wanted is missing' do
    expect(described_class.find(contents, 'blood', use_yaba: true)).to equal(yaba)
    expect(described_class.find({ all: [tincture], edible: [], drinkable: [tincture] }, 'blood')).to equal(tincture)
    expect(described_class.find(contents, 'missing eye')).to be_nil
  end

  it 'finds a herb for a type already in hand' do
    stub_const('GameObj', Class.new { define_singleton_method(:right_hand) { nil } })
    held = [obj.new(nil, 'Empty', nil), leaf]
    allow(GameObj).to receive_messages(right_hand: held[0], left_hand: held[1])
    expect(described_class.in_hand('blood')).to equal(leaf)
    expect(described_class.in_hand('disease')).to be_nil
  end

  it 'passes over the areas a missing herb would have treated' do
    expect(described_class.skip_for('major head wound')).to eq(%w[head neck])
    expect(described_class.skip_for('missing eye')).to eq(['torso'])
    expect(described_class.skip_for('severed limb')).to eq(['limbs'])
    expect(described_class.skip_for('blood')).to eq(['blood'])
  end

  describe '.use' do
    it 'eats a herb and drinks a potion, waiting out roundtime after' do
      answers[/my/] = ['You take a bite of your leaf.']
      expect(described_class.use(leaf)).to eq(:used)
      described_class.use(tincture)
      described_class.use(leaf, drinkable: true)
      expect(sent).to eq(['eat my leaf', :wait, 'drink my tincture', :wait, 'drink my leaf', :wait])
    end

    it 'eats it where it lies when told not to pick it up' do
      described_class.use(tincture, no_get: true)
      expect(sent.first).to eq('eat tincture')
    end

    it 'says what the answer means' do
      answers['eat my leaf'] = [['You must pick the leaf up first.'], ["Why don't you leave some for others?"], []]
      expect(Array.new(3) { described_class.use(leaf) }).to eq(%i[must_take enough no_answer])
    end
  end
end

RSpec.describe EO::Herbs::Shop do
  include_context 'a script lending helpers'

  let(:obj) { Struct.new(:id, :name, :noun, :full_name, keyword_init: true) }
  let(:fputs) { [] }
  let(:replies) { [] }

  before do
    EO.use(script: 'spec', lines: ->(text, _pattern) { sent << text && answer_to(text) })
    log = fputs
    queue = replies
    described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    described_class.define_singleton_method(:dothistimeout) { |cmd, *_| log << cmd && queue.shift }
    $eherbs_measure = {}
  end

  after do
    %i[fput dothistimeout].each { |m| described_class.singleton_class.remove_method(m) }
    $eherbs_measure = nil
  end

  it 'reads the menu, names without their article to their numbers' do
    answers['order'] = [%q(<d cmd="order 1">some acantha leaf</d>  <d cmd='order 12'>a tincture of acantha</d>)]
    expect(described_class.menu).to eq('some acantha leaf' => '1', 'tincture of acantha' => '12')
  end

  it 'finds on a menu what treats a type' do
    menu = { 'some wolifrew lichen' => '3', 'some acantha leaf' => '1' }
    expect(described_class.on_menu(menu, 'blood')).to eq('some acantha leaf')
    expect(described_class.on_menu(menu, 'minor blood')).to eq('some acantha leaf')
    expect(described_class.on_menu(menu, 'missing eye')).to be_nil
  end

  it 'orders, and clears both hands into the sack when a free hand is wanted' do
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { Struct.new(:id).new('1') }
      define_singleton_method(:left_hand) { Struct.new(:id).new('2') }
    end)
    replies.push('You ask for an order. BUY to confirm.', 'You will need a free hand.')
    described_class.order(1, '3', 'sack')
    described_class.order(2, '3', 'sack')
    expect(fputs).to eq(['order 1 3', 'order 2 3', 'put #1 in sack', 'put #2 in sack'])
  end

  it 'buys, records the doses of what lands in hand, and says how it went' do
    leaf = obj.new(id: '60', name: 'some acantha leaf')
    stub_const('GameObj', Class.new { define_singleton_method(:left_hand) { nil } })
    allow(GameObj).to receive_messages(right_hand: leaf, left_hand: obj.new(name: 'Empty'))
    replies.push('Sold for 100 silver.', 'But you do not have enough silver!', "You're going to need a free hand.", nil)
    expect(Array.new(4) { described_class.buy }).to eq(%i[sold no_silver no_hand other])
    expect($eherbs_measure).to eq('60' => 10)
  end

  it 'reads a price from the order line' do
    answers['order 3'] = ['You ask the herbalist.  "That will be 1,250 silvers," she says.']
    expect(described_class.price('3')).to eq(1250)
    expect(described_class.price('4')).to be_nil
  end

  it 'finds what a place sells for a heading, in the form asked for' do
    expect(described_class.sold('blood', "Ta'Illistim")[:name]).to eq('some acantha leaf')
    expect(described_class.sold('blood', "Ta'Illistim", 'drinkable')[:name]).to match(EO::Herbs::Table::DRINKABLE)
    expect(described_class.sold('blood', 'the moon')).to be_nil
  end

  it 'counts the doses of what the sack holds for a heading' do
    leaf = obj.new(id: '7', name: 'some acantha leaf')
    lichen = obj.new(id: '8', name: 'some wolifrew lichen')
    contents = { all: [leaf, lichen], edible: [leaf, lichen], drinkable: [] }
    $eherbs_measure.merge!('7' => 6, '8' => 4)
    held = described_class.held(contents, 'blood')
    expect(held).to eq([leaf])
    expect(described_class.doses(held)).to eq(6)
    expect(described_class.held(contents, 'blood', 'drinkable')).to be_empty
  end

  it 'bundles everything of a herb into one, measures it and puts it back' do
    first = obj.new(id: '7', name: 'some acantha leaf', full_name: 'some acantha leaf')
    second = obj.new(id: '8', name: 'some acantha leaf', full_name: 'some acantha leaf')
    sack = Struct.new(:id, :contents).new('4', [first, second])
    bundle = obj.new(id: '7', name: 'bundle of acantha leaf')
    stub_const('GameObj', Class.new { define_singleton_method(:right_hand) { nil } })
    allow(GameObj).to receive(:right_hand).and_return(bundle)
    allow(EO::Herbs::Sack).to receive(:take)
    allow(EO::Herbs::Sack).to receive(:put)
    described_class.define_singleton_method(:dothis) { |*_| 'Carefully, you combine all your acantha leaf into one bundle.' }

    expect(described_class.bundle_all(sack, 'some acantha leaf')).to be_nil
    expect(EO::Herbs::Sack).to have_received(:take).twice
    expect(fputs).to eq(['measure #7'])
    expect(EO::Herbs::Sack).to have_received(:put).with('7', '4')
  ensure
    described_class.singleton_class.remove_method(:dothis)
  end

  it 'stops bundling when the sack will give no more' do
    items = Array.new(2) { |i| obj.new(id: i.to_s, name: 'some acantha leaf', full_name: 'some acantha leaf') }
    allow(EO::Herbs::Sack).to receive(:take).and_return(:enough)
    expect(described_class.bundle_all(Struct.new(:id, :contents).new('4', items), 'some acantha leaf')).to eq(:enough)
  end
end
