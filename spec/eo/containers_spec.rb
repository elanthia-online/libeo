# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/containers'

RSpec.describe EO::Containers do
  include_context 'a script lending helpers'

  let(:bag_type) { Struct.new(:id, :name, :contents) }
  let(:bag) { bag_type.new('7', 'leather sack', nil) }
  let(:known) { {} }

  before do
    containers = known
    stub_const('GameObj', Class.new { define_singleton_method(:containers) { containers } })
    allow(described_class).to receive(:sleep)
  end

  def listed!(contents = [])
    known[bag.id] = contents
    bag.contents = contents
  end

  describe '.listed?' do
    it 'needs both the container among those Lich has and its contents' do
      expect(described_class.listed?(bag)).to be(false)
      known[bag.id] = []
      expect(described_class.listed?(bag)).to be(false)
      bag.contents = []
      expect(described_class.listed?(bag)).to be(true)
    end
  end

  describe 'with the inventory feed' do
    let(:fed) { Struct.new(:closed?, :locked?) }
    let(:feed) { {} }

    before do
      items = feed
      log = sent
      stub_const('Lich::Common::Inventory', Class.new do
        define_singleton_method(:refresh) { log << :refresh && items }
        define_singleton_method(:[]) { |id| items[id] }
        define_singleton_method(:last_updated) { Time.now }
      end)
    end

    it 'sends an open container nothing, and a locked one nothing' do
      feed['7'] = fed.new(false, false)
      expect(described_class.ensure_open(bag)).to eq(:listed)
      feed['7'] = fed.new(true, true)
      expect(described_class.ensure_open(bag)).to eq(:locked)
      expect(sent).to eq(%i[refresh refresh])
    end

    it 'opens a closed one, and does not look in' do
      feed['7'] = fed.new(true, false)
      listed!
      expect(described_class.ensure_open(bag)).to eq(:opened)
      expect(sent).to eq([:refresh, 'open #7'])
    end

    it 'goes on as before with a container the feed does not know' do
      answers['look in #7'] = ['In the disk you see a ruby.']
      expect(described_class.ensure_open(bag)).to eq(:opened)
      expect(sent).to eq([:refresh, 'open #7', 'look in #7'])
    end

    it 'reads fresh contents from the feed, with no LOOK IN' do
      feed['7'] = fed.new(false, false)
      listed!(%w[ruby])
      expect(described_class.fresh_contents(bag)).to eq(%w[ruby])
      expect(sent).to eq([:refresh])
    end

    it 'says what the feed last heard of a container, without asking' do
      feed['7'] = fed.new(true, false)
      expect(described_class.feed?).to be(true)
      expect(described_class.closed?(bag)).to be(true)
      expect(described_class.closed?(bag_type.new('99', 'a disk', nil))).to be_nil
      expect(sent).to be_empty
    end
  end

  describe '.ensure_open' do
    it 'leaves a listed container alone' do
      listed!
      expect(described_class.ensure_open(bag)).to eq(:listed)
      expect(sent).to be_empty
    end

    it 'opens any other and looks in' do
      answers['look in #7'] = ['In the <a exist="7" noun="sack">leather sack</a> you see a ruby.']
      expect(described_class.ensure_open(bag)).to eq(:opened)
      expect(sent).to eq(['open #7', 'look in #7'])
    end

    it 'tells an empty one, and one the game does not itemise' do
      answers['look in #7'] = [['There is nothing in there.'], ['Looking at the neck sheath, you notice: a dagger']]
      expect(described_class.ensure_open(bag)).to eq(:nothing)
      expect(described_class.ensure_open(bag)).to eq(:nothing)
    end
  end

  describe '.contents_ready?' do
    it 'is ready at once for a listed container' do
      listed!
      expect(described_class.contents_ready?(bag)).to be(true)
      expect(sent).to be_empty
      expect(said).to be_empty
    end

    it 'looks in once more when they do not come, and says so' do
      answers['look in #7'] = ['You glance at the sack.']
      expect(described_class.contents_ready?(bag, seconds: 1, from: 'eloot.lic:100')).to be(true)
      expect(sent).to eq(['look in #7'])
      expect(said.size).to eq(1)
      expect(said.first.last).to include('This failed the first time. Trying again. | Container: leather sack', 'caller: eloot.lic:100')
    end

    it 'gives up after the second wait, with what it could not read' do
      expect(described_class.contents_ready?(bag, seconds: 1)).to be(false)
      expect(said.map(&:last).last).to eq(' Unable to determine the contents of  leather sack.')
      expect(said.size).to eq(3)
      expect(described_class).to have_received(:sleep).with(0.1).exactly(20).times
    end
  end

  describe '.fresh_contents' do
    it 'looks in before reading, and has nothing for no container' do
      bag.contents = [:ruby]
      expect(described_class.fresh_contents(bag)).to eq([:ruby])
      expect(sent).to eq(['look in #7'])
      expect(described_class.fresh_contents(nil)).to eq([])
    end
  end

  describe '.close' do
    it 'closes by id and answers with the line' do
      answers['close #7'] = ['You close the sack.']
      expect(described_class.close(bag)).to eq('You close the sack.')
    end
  end
end
