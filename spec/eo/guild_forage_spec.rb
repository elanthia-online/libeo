# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/guild/forage'
require_relative '../../scripts/eo/guild/heirloom'
require_relative '../../scripts/eo/wander'

RSpec.describe EO::Guild::Forage do
  include_context 'a script lending helpers'

  let(:item) { Struct.new(:id, :name, :noun) }
  let(:sack) { Struct.new(:contents) { def to_s = 'sack' }.new([]) }
  let(:fputs) { [] }
  let(:hands) { { right: item.new(nil, 'Empty', nil), left: item.new(nil, 'Empty', nil) } }
  let(:state) { { bounty: 'task', hidden: false, right: false } }

  before do
    stow = sack
    held = hands
    now = state
    log = fputs
    stub_const('StowList', Class.new { define_singleton_method(:stow_list) { { default: stow } } })
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { held[:right] }
      define_singleton_method(:left_hand) { held[:left] }
    end)
    described_class.define_singleton_method(:fput) { |cmd| log << cmd }
    described_class.define_singleton_method(:checkbounty) { now[:bounty] }
    described_class.define_singleton_method(:checkhidden) { now[:hidden] }
    described_class.define_singleton_method(:checkright) { now[:right] }
    described_class.define_singleton_method(:checkleft) { false }
  end

  after { %i[fput checkbounty checkhidden checkright checkleft].each { |m| described_class.singleton_class.remove_method(m) } }

  describe '.rooms' do
    let(:room_type) { Struct.new(:id, :tags, :location) }
    let(:rooms) do
      [room_type.new(1, ['acantha leaf'], 'the forest'), room_type.new(2, ['some acantha leaf'], 'the hills'),
       room_type.new(3, ['wolifrew lichen'], 'the forest'), room_type.new(4, ['acantha leaf'], 'the far forest')]
    end

    before do
      all = rooms
      stub_const('Room', Class.new do
        define_singleton_method(:list) { all }
        define_singleton_method(:[]) { |id| all.find { |r| r.id == id } }
        define_singleton_method(:current) { Struct.new(:dijkstra).new([{}, { 1 => 40, 2 => 10, 4 => 200 }]) }
      end)
    end

    it 'lists the rooms the herb grows in, nearest first, within ninety steps' do
      expect(described_class.rooms('some acantha leaf', 'acantha leaf', 'nearest')).to eq([2, 1])
    end

    it 'keeps to a named place, however far' do
      expect(described_class.rooms('some acantha leaf', 'acantha leaf', 'the far forest')).to eq([4])
    end
  end

  it 'finds the herbs held, a mushroom by the name it carries' do
    sack.contents.push(item.new('1', 'white hook mushroom'), item.new('2', 'some acantha leaf'), item.new('3', 'ayana'))
    expect(described_class.held('white mushroom').map(&:id)).to eq(['1'])
    expect(described_class.held('acantha leaf').map(&:id)).to eq(['2'])
    expect(described_class.held('ayana leaf').map(&:id)).to eq(['3'])
  end

  it 'reads what to forage for from the link BOUNTY gives' do
    stub_const('Char', Class.new { define_singleton_method(:name) { 'Nisugi' } })
    answers['bounty'] = [%q(She is working on a concoction that requires <d cmd="forage acantha leaf">some acantha leaf</d> found near town.)]
    expect(described_class.linked_item).to eq('acantha leaf')
    answers['bounty'] = ['You are not currently assigned a task.']
    expect(described_class.linked_item).to be_nil
  end

  it 'forages once and waits out the roundtime' do
    answers['forage for acantha leaf'] = ['You forage briefly and manage to find some acantha leaf!']
    expect(described_class.try('acantha leaf')).to match(described_class::FOUND)
    expect(sent).to eq(['forage for acantha leaf', :wait])
  end

  it 'tells a room without the herb from one picked over' do
    expect('As you carefully forage around you can find no hint of what you are looking for.').to match(described_class::NOT_HERE)
    expect('As you forage around, you notice that someone has been foraging here recently and you are unable to find anything useful.').to match(described_class::PICKED_OVER)
  end

  describe '.stow_found' do
    before { hands[:right] = item.new('7', 'some acantha leaf', 'leaf') }

    it 'puts the find in the sack until it is seen there, five tries at most' do
      described_class.stow_found(gambits: false)
      expect(fputs).to eq(['put my leaf in my sack'] * 5)
    end

    it 'uses the stealth gambit while hidden, when there is one' do
      state[:hidden] = true
      found = hands[:right]
      allow(EO).to receive(:settle) do
        hands[:right] = item.new(nil, 'Empty', nil)
        sack.contents << found
      end
      described_class.stow_found(gambits: true)
      expect(fputs).to eq(['rgambit stealth put my leaf in my sack'])
    end
  end

  describe '.give' do
    let(:herbs) { [item.new('1', 'leaf'), item.new('2', 'leaf'), item.new('3', 'leaf')] }

    before { answers[/give #2/] = ['That looks like it has been partially used up.'] }

    it 'stops at a herb that is refused, stowing it' do
      state[:right] = true
      answers[/give #1/] = ['This looks perfect.']
      described_class.give(herbs, to: 'herbalist', past_refusals: false)
      expect(sent).to eq(['_drag #1 right', 'give #1 to herbalist', '_drag #2 right', 'give #2 to herbalist', 'stow #2'])
    end

    it 'goes on to the rest when told to' do
      described_class.give(herbs, to: '#9', past_refusals: true)
      expect(sent.grep(/^give/)).to eq(['give #1 to #9', 'give #2 to #9', 'give #3 to #9'])
    end
  end
end

RSpec.describe EO::Guild::Heirloom do
  include_context 'a script lending helpers'

  it 'steps to a room not yet visited, never across a boundary' do
    moves = []
    room = Struct.new(:wayto, :timeto).new({ '2' => 'north', '3' => 'east', '4' => 'west' }, { '2' => 0.2, '3' => 0.2, '4' => 0.2 })
    stub_const('Room', Class.new { define_singleton_method(:current) { room } })
    described_class.define_singleton_method(:move) { |way| moves << way }
    visited = ['2']
    described_class.wander(visited, ['4'])
    described_class.wander(visited, ['4'])
    expect(moves).to eq(%w[east north])
  ensure
    described_class.singleton_class.remove_method(:move)
  end

  it 'searches kneeling with empty hands, and stows what the search put in the right hand' do
    log = []
    state = { right: false }
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { Struct.new(:id).new('5') }
      define_singleton_method(:loot) { [] }
    end)
    described_class.define_singleton_method(:fput) { |cmd| log << cmd && state[:right] = true }
    described_class.define_singleton_method(:checkright) { state[:right] }
    described_class.define_singleton_method(:checkleft) { false }
    described_class.search('silver ring')
    expect(log).to eq(['search'])
    expect(sent).to eq([:wait, 'stow #5'])
  ensure
    %i[fput checkright checkleft].each { |m| described_class.singleton_class.remove_method(m) }
  end
end
