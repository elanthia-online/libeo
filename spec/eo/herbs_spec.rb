# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/herbs/table'
require_relative '../../scripts/eo/herbs/injuries'

RSpec.describe EO::Herbs::Table do
  let(:acantha) { described_class::KNOWN.find { |h| h[:name] == 'some acantha leaf' } }
  let(:yaba) { described_class::KNOWN.find { |h| h[:short_name] == 'tincture of yabathilium' } }

  it 'holds every herb with where it is sold, what it treats and its doses' do
    expect(described_class::KNOWN.size).to eq(247)
    expect(described_class::KNOWN).to all(include(:location, :name, :type, :short_name, :store_doses))
    expect(acantha).to include(type: 'blood', store_doses: 10)
  end

  it 'has a stock target for every type a herb treats but poison, disease and the two for the dead' do
    types = described_class::KNOWN.map { |h| h[:type] }.uniq - %w[poison disease lifekeep raisedead]
    expect(types - described_class::DEFAULT_DOSES.keys).to be_empty
  end

  it 'tells the stronger restoratives of blood from the rest' do
    expect(described_class.major_blood?(yaba)).to be(true)
    expect(described_class.major_blood?(acantha)).to be(false)
    expect(described_class.blood_tier(acantha)).to eq('minor blood')
    expect(described_class.blood_tier(type: 'poison')).to eq('poison')
  end

  it 'counts blood as one heading unless it is split' do
    expect(described_class.blood_bucket(yaba, split: false)).to eq('blood')
    expect(described_class.blood_bucket(yaba, split: true)).to eq('major blood')
    expect(described_class.blood_bucket({ type: 'disease' }, split: true)).to eq('disease')
  end

  it 'puts a herb under its type, and a blood herb under blood and its tier' do
    expect(described_class.in_category?(yaba, 'blood')).to be(true)
    expect(described_class.in_category?(yaba, 'major blood')).to be(true)
    expect(described_class.in_category?(yaba, 'minor blood')).to be(false)
    expect(described_class.in_category?(acantha, 'poison')).to be(false)
  end

  it 'knows where herbs are sold' do
    expect(described_class.sold_at?("Ta'Illistim")).to be(true)
    expect(described_class.sold_at?('the moon')).to be(false)
    expect(described_class.sold_at?(nil)).to be(false)
  end

  it 'knows what is drunk by its name' do
    expect('tincture of acantha').to match(described_class::DRINKABLE)
    expect('some acantha leaf').not_to match(described_class::DRINKABLE)
  end
end

RSpec.describe EO::Herbs::Injuries do
  let(:wounds) { Hash.new(0) }
  let(:scars) { Hash.new(0) }
  let(:char) { { percent: 100, health: 200, max: 200, poison: false, disease: false } }

  before do
    { 'Wounds' => wounds, 'Scars' => scars }.each do |name, marks|
      stub_const(name, Class.new do
        define_singleton_method(:method_missing) { |part, *_| marks[part.to_s] }
        define_singleton_method(:respond_to_missing?) { |*_| true }
      end)
    end
    now = char
    stub_const('Char', Class.new do
      define_singleton_method(:percent_health) { now[:percent] }
      define_singleton_method(:health) { now[:health] }
      define_singleton_method(:max_health) { now[:max] }
    end)
    described_class.define_singleton_method(:checkpoison) { now[:poison] }
    described_class.define_singleton_method(:checkdisease) { now[:disease] }
  end

  after { %i[checkpoison checkdisease].each { |m| described_class.singleton_class.remove_method(m) } }

  describe '.next_type' do
    it 'calls for nothing when nothing is wrong' do
      expect(described_class.next_type).to be_nil
    end

    it 'puts blood first under half health, then poison and disease' do
      char.merge!(percent: 40, poison: true, disease: true)
      expect(described_class.next_type).to eq('blood')
      expect(described_class.next_type(skip: ['blood'])).to eq('poison')
      expect(described_class.next_type(skip: %w[blood poison])).to eq('disease')
    end

    it 'treats wounds before scars, and major before minor' do
      wounds['limbs'] = 1
      scars['head'] = 2
      expect(described_class.next_type).to eq('minor limb wound')
      wounds['torso'] = 2
      expect(described_class.next_type).to eq('major organ wound')
      wounds.clear
      expect(described_class.next_type).to eq('major head scar')
    end

    it 'calls a limb scarred to rank 3 severed, and an eye missing' do
      scars['limbs'] = 3
      expect(described_class.next_type).to eq('severed limb')
      scars.clear
      scars['leye'] = 3
      expect(described_class.next_type).to eq('missing eye')
    end

    it 'leaves a minor scar when told to, and an area passed over' do
      scars['nerves'] = 1
      expect(described_class.next_type).to eq('minor nerve scar')
      expect(described_class.next_type(skip_scars: true)).to be_nil
      expect(described_class.next_type(skip: ['nerves'])).to be_nil
    end

    it 'tops up blood last, when anything is missing from health' do
      char[:health] = 180
      expect(described_class.next_type).to eq('blood')
    end

    it 'treats only arms and hands for shooting, and the head, eyes and nerves too for casting' do
      wounds.merge!('head' => 2, 'leftHand' => 1, 'limbs' => 1)
      expect(described_class.next_type(ranged_only: true)).to eq('minor limb wound')
      wounds['leftHand'] = 0
      expect(described_class.next_type(ranged_only: true)).to be_nil
      expect(described_class.next_type(spellcast_only: true)).to eq('major head wound')
      wounds.clear
      wounds['rightEye'] = 1
      expect(described_class.next_type(spellcast_only: true)).to eq('minor organ wound')
    end
  end

  describe '.appraise' do
    it 'finds only the bleeding wounds unless asked for all' do
      lines = ['She has deep lacerations across her chest, and a bruised left eye.']
      expect(described_class.appraise(lines)).to eq(['major organ wound'])
      expect(described_class.appraise(lines, full: true)).to eq(['major organ wound', 'minor organ wound'])
    end

    it 'comes to the scars only when there are no wounds' do
      expect(described_class.appraise(['He has a missing right eye and a scar across his face.'], full: true)).to eq(['missing eye', 'minor head scar'])
      expect(described_class.appraise(['He has a missing right arm.'], full: true)).to eq(['severed limb'])
    end
  end

  it 'reads what an escort needs from how LOOK describes them' do
    expect(described_class.escort('He has moderate bleeding from his neck.')).to eq(['major head wound', 'minor head wound'])
    expect(described_class.escort('She has a swollen left eye and minor bruises about the head.')).to eq(['major organ wound', 'minor organ wound', 'minor head wound'])
    expect(described_class.escort('He appears to be in good shape.')).to eq([])
  end

  it "reports the character's condition type by type" do
    described_class.define_singleton_method(:checkdead) { false }
    wounds['neck'] = 2
    scars['rleg'] = 3
    status = described_class.status
    expect(status['major head wound']).to be(true)
    expect(status['minor head wound']).to be(false)
    expect(status['severed limb']).to be(true)
    expect(status['blood']).to be(false)
  ensure
    described_class.singleton_class.remove_method(:checkdead)
  end
end
