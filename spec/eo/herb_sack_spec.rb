# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/herbs/table'
require_relative '../../scripts/eo/herbs/doses'
require_relative '../../scripts/eo/herbs/sack'

RSpec.describe EO::Herbs::Doses::Monitor do
  let(:monitor) { described_class.new }

  before do
    $eherbs_measure = {}
    stub_const('GameObj', Class.new { define_singleton_method(:right_hand) { Struct.new(:id).new('50') } })
  end

  after { $eherbs_measure = nil }

  def read(*lines) = lines.each { |line| monitor.read(line) }

  it 'hands every line back unchanged' do
    expect(monitor.read('anything at all')).to eq('anything at all')
  end

  it 'counts down a herb as it is eaten, until the prompt' do
    read('You take a bite of your <a exist="7" noun="leaf">acantha leaf</a>.', 'You have 3 bites left.')
    expect($eherbs_measure['7']).to eq(3)
    read('<prompt time="1">&gt;</prompt>', 'You have 9 bites left.')
    expect($eherbs_measure['7']).to eq(3)
  end

  it 'reads the last of a potion' do
    read('You take a drink from your <a exist="8" noun="potion">potion</a>.', 'That was the last drop.')
    expect($eherbs_measure['8']).to eq(0)
  end

  it 'takes a measure the game gives in numbers as it is' do
    read('The <a exist="9" noun="potion">potion</a> has 6 doses left.', 'The <a exist="7" noun="leaf">leaf</a> has 1 bite left.')
    expect($eherbs_measure).to eq('9' => 6, '7' => 1)
  end

  it 'guesses for a measure given in words, unless what it holds already agrees' do
    read('The <a exist="9" noun="potion">potion</a> has several doses left.')
    expect($eherbs_measure['9']).to eq(7)
    $eherbs_measure['9'] = 6
    read('The <a exist="9" noun="potion">potion</a> has several doses left.')
    expect($eherbs_measure['9']).to eq(6)
    read('The <a exist="9" noun="potion">potion</a> has a few doses left.')
    expect($eherbs_measure['9']).to eq(4)
  end

  it 'adds what was just bought to a bundle it has a count for' do
    $eherbs_measure['50'] = 10
    read('She hands you <a exist="60" noun="leaf">some acantha leaf</a> and says, "Here\'s your purchase.', 'Carefully, you combine all your acantha leaf into one bundle.')
    expect($eherbs_measure['50']).to eq(20)
  end

  it 'counts a dose taken off a bundle, into the left hand' do
    $eherbs_measure['50'] = 10
    read('<left exist="61" noun="leaf">leaf</left>', 'You carefully remove one dose from your <a exist="50" noun="leaf">bundle</a>.')
    expect($eherbs_measure).to include('50' => 9, '61' => 1)
  end
end

RSpec.describe EO::Herbs::Sack do
  include_context 'a script lending helpers'

  let(:obj) { Struct.new(:id, :noun, :name, :type, :contents, keyword_init: true) { def empty? = false } }
  let(:empty) { obj.new(id: nil, name: 'Empty') }
  let(:hands) { { right: empty, left: empty } }
  let(:known) { {} }
  let(:fputs) { [] }
  let(:hurt) { Hash.new(0) }

  before do
    held = hands
    listed = known
    maker = obj
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
      define_singleton_method(:containers) { listed }
      define_singleton_method(:new_inv) { |id, noun, name, _container| maker.new(id: id, noun: noun, name: name, type: 'herb') }
    end)
    marks = hurt
    %w[Wounds Scars].each do |kind|
      stub_const(kind, Class.new do
        %i[rightArm rightHand leftArm leftHand].each { |part| define_singleton_method(part) { marks[[kind, part]] } }
      end)
    end
    EO.use(script: 'spec', lines: ->(text, _pattern) { sent << text && answer_to(text) })
    log = fputs
    described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    described_class.define_singleton_method(:waitrt?) { nil }
    described_class.define_singleton_method(:checkright) { !held[:right].id.nil? }
    described_class.define_singleton_method(:checkleft) { !held[:left].id.nil? }
    allow(described_class).to receive(:sleep)
  end

  after { %i[fput waitrt? checkright checkleft].each { |m| described_class.singleton_class.remove_method(m) } }

  describe '.open' do
    let(:sack) { obj.new(id: '4', name: 'herb sack') }

    it 'leaves a container Lich already has the contents of' do
      known['4'] = []
      sack.contents = []
      expect(described_class.open(sack)).to be_nil
      expect(sent).to be_empty
    end

    it 'opens and looks in, and says when it was the one to open it' do
      answers['open #4'] = ['You open the sack.']
      answers['look in #4'] = ['There is nothing in there.']
      opened = []
      described_class.open(sack) { opened << true }
      expect(opened).to eq([true])
      expect(sent).to eq(['open #4', 'look in #4'])
    end

    it 'tells a locked one, and does not claim to have opened one that was open' do
      answers['open #4'] = [['It appears to be locked.'], ['That is already open.']]
      opened = []
      expect(described_class.open(sack) { opened << true }).to eq(:locked)
      described_class.open(sack) { opened << true }
      expect(opened).to be_empty
    end
  end

  it 'sorts herbs into what is drunk and what is eaten, and leaves what is no herb' do
    leaf = obj.new(name: 'some acantha leaf', type: 'herb')
    tincture = obj.new(name: 'tincture of acantha', type: 'herb')
    forms = described_class.by_form([leaf, tincture, obj.new(name: 'a ruby', type: 'gem')])
    expect(forms).to eq(drinkable: [tincture], edible: [leaf], all: [leaf, tincture])
  end

  it 'reads the herbs on something in the room, keeping the ones the table knows' do
    bench = obj.new(id: '30', name: 'bench')
    answers['look on #30'] = ['On the <a exist="30" noun="bench">bench</a> you see <a exist="31" noun="leaf">some acantha leaf</a> and <a exist="32" noun="rock">a rock</a>.']
    expect(described_class.room_contents(bench, 'on').map(&:id)).to eq(['31'])
  end

  it 'opens a closed container in the room and looks again, or says it is locked' do
    chest = obj.new(id: '30', name: 'chest')
    listing = 'In the <a exist="30" noun="chest">chest</a> you see <a exist="31" noun="leaf">some acantha leaf</a>.'
    # opening looks in too, so the listing is read twice
    answers['look in #30'] = [['That is closed.'], [listing], [listing], ['That is closed.']]
    answers['open #30'] = [['You open the chest.'], ['It appears to be locked.']]
    expect(described_class.room_contents(chest, 'in').map(&:id)).to eq(['31'])
    expect(described_class.room_contents(chest, 'in')).to eq(:locked)
  end

  it 'puts an item in a container, in it unless told where' do
    described_class.put('7', '4')
    described_class.put('7', '30', 'on')
    expect(sent).to eq(['put #7 in #4', 'put #7 on #30'])
  end

  describe '.take' do
    let(:leaf) { obj.new(id: '7', name: 'some acantha leaf') }

    it 'drags to the right hand when it is empty, else the left' do
      described_class.take(leaf)
      hands[:right] = obj.new(id: '1', name: 'sword')
      described_class.take(leaf)
      expect(sent).to eq(['_drag #7 right', '_drag #7 left'])
    end

    it 'says when the answer shows a drink, and when the game will give no more' do
      answers['_drag #7 right'] = [['You remove a tincture of acantha from your sack.'], ["Why don't you leave some for others?"], ['You remove a leaf.']]
      expect([described_class.take(leaf), described_class.take(leaf), described_class.take(leaf)]).to eq([true, :enough, nil])
    end

    it 'stows the right hand to make room when both are full' do
      hands.replace(right: obj.new(id: '1', name: 'sword'), left: obj.new(id: '2', name: 'shield'))
      described_class.take(leaf)
      expect(fputs.size).to eq(1)
      expect(fputs.first).to start_with('stow ')
    end
  end
end
