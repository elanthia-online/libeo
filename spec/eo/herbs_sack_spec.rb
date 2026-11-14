# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/guild/tables'
require_relative '../../scripts/eo/herbs/table'
require_relative '../../scripts/eo/herbs/doses'
require_relative '../../scripts/eo/herbs/sack'

# The container the herbs live in. The herb table is the real one; the game's
# own calls (GameObj, the wounds, the commands) are stood in for.
RSpec.describe EO::Herbs::Sack do
  let(:item) { Struct.new(:id, :name, :noun, :type, :contents, keyword_init: true) }
  let(:backpack) { item.new(id: '10', name: 'leather backpack', noun: 'backpack', contents: []) }
  let(:sack) { described_class.new(backpack) }
  let(:acantha) { item.new(id: '5', name: 'tincture of acantha', noun: 'tincture', type: 'herb') }

  def inventory(*things)
    stub_const('GameObj', Class.new do
      define_singleton_method(:inv) { things }
      define_singleton_method(:room_desc) { [] }
      define_singleton_method(:loot) { [] }
    end)
  end

  # right, left: the ids held, nil for an empty hand
  def hands(right: nil, left: nil)
    thing = Struct.new(:id, :label) { def to_s = label }
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { thing.new(right, 'right thing') }
      define_singleton_method(:left_hand) { thing.new(left, 'left thing') }
    end)
  end

  describe '.find and .named' do
    it 'finds a carried container by a word of its name, whatever the case' do
      inventory(backpack)
      expect(described_class.find('Backpack').obj).to eq(backpack)
      expect(described_class.find('leather').obj).to eq(backpack)
    end

    it 'does not take part of a word for the word' do
      inventory(backpack)
      expect { described_class.find('pack') }.to raise_error(EO::Guild::Error, /unable to find container "pack"/)
    end

    it 'finds a container in the room when the inventory has none, with its preposition' do
      bench = item.new(id: '20', name: 'wooden bench', noun: 'bench')
      stub_const('GameObj', Class.new do
        define_singleton_method(:inv) { [] }
        define_singleton_method(:room_desc) { [bench] }
        define_singleton_method(:loot) { [] }
      end)
      found = described_class.named('bench', preposition: 'on')
      expect(found.obj).to eq(bench)
      expect(found.preposition).to eq('on')
      expect { described_class.named('cart') }.to raise_error(EO::Guild::Error, /not able to find a cart/)
    end

    it 'says it is carried only when the inventory holds it' do
      inventory(backpack)
      expect(sack).to be_carried
      inventory
      expect(sack).not_to be_carried
    end
  end

  describe '#stock_targets' do
    let(:defaults) { EO::Herbs::Table::DEFAULT_DOSES }

    it 'scales an ordinary sack from the default doses, dropping the fraction' do
      targets = sack.stock_targets(50)
      expect(targets['blood']).to eq(25)
      expect(targets['missing eye']).to eq(3) # 7 * 0.5
      expect(targets.keys).to eq(defaults.keys)
    end

    it 'never aims above a full sack' do
      expect(sack.stock_targets(150)).to eq(defaults)
    end

    it "sets every type to a kit's capacity by tier" do
      sack.survival_kit = true
      sack.instance_variable_set(:@tier, 2)
      expect(sack.stock_targets(100).values.uniq).to eq([75]) # (2 * 25) + 25
      expect(sack.stock_targets(50).values.uniq).to eq([37])
    end
  end

  describe '#by_form' do
    it 'keeps herbs only, split into drinkable and edible' do
      stray = item.new(id: '7', name: 'silver ring', noun: 'ring', type: 'jewelry')
      sprig = item.new(id: '8', name: 'sprig of acantha leaf', noun: 'leaf', type: 'herb')
      forms = sack.by_form([acantha, sprig, stray])
      expect(forms[:drinkable]).to eq([acantha])
      expect(forms[:edible]).to eq([sprig])
      expect(forms[:all]).to eq([acantha, sprig])
    end
  end

  describe '#analyze!' do
    def analyze_with(lines)
      allow(EO).to receive(:command).and_return(lines)
      sack.analyze!
    end

    it 'knows an ordinary sack' do
      expect(analyze_with(['You analyze the sack.  It is a leather backpack.'])).to be(false)
      expect(sack.survival_kit).to be(false)
      expect(sack.distiller).to be(false)
    end
  end

  describe '#store' do
    it "puts the item in by its id, using the sack's preposition" do
      sent = []
      allow(EO).to receive(:result) do |cmd, _|
        sent << cmd
        'You put your tincture in your backpack.'
      end
      sack.store(acantha)
      sack.store('99')
      expect(sent).to eq(['put #5 in #10', 'put #99 in #10'])
    end

    it 'says so when the sack will not take it' do
      allow(EO).to receive(:result).and_return("Your tincture won't fit in your backpack.")
      expect { sack.store(acantha) }.to raise_error(described_class::Full, /backpack is full/)
    end
  end

  describe '#put_back' do
    it 'stows what a full sack would not take, if it is still in a hand' do
      allow(EO).to receive(:result).and_return("Your tincture won't fit in your backpack.")
      hands(right: '5')
      allow(sack).to receive(:fput)
      sack.put_back(acantha)
      expect(sack).to have_received(:fput).with('stow #5')
    end

    it 'leaves it alone once the sack has taken it' do
      allow(EO).to receive(:result).and_return('You put your tincture in your backpack.')
      hands
      allow(sack).to receive(:fput)
      sack.put_back(acantha)
      expect(sack).not_to have_received(:fput)
    end
  end

  describe '#take' do
    # answer: what the game says; right: the id in the right hand
    def take_with(answer, right: nil)
      sent = []
      hands(right: right)
      allow(sack).to receive(:free_hand)
      allow(EO).to receive(:result) do |cmd, _|
        sent << cmd
        answer
      end
      [sack.take(acantha), sent]
    end

    it 'drags into the right hand when it is empty, the left when it is not' do
      expect(take_with('You remove a tincture of acantha from your backpack.').last).to eq(['_drag #5 right'])
      expect(take_with('You remove a tincture of acantha from your backpack.', right: '1').last).to eq(['_drag #5 left'])
    end

    it 'says whether it is drunk' do
      expect(take_with('You remove a tincture of acantha.').first).to be(true)
      expect(take_with('You remove a sprig of acantha leaf.').first).to be(false)
    end

    it 'stops when the game says enough has been eaten from here' do
      expect { take_with("Why don't you leave some for others?") }.to raise_error(EO::Guild::Error, /eaten enough/)
    end
  end

  describe '#free_hand' do
    # right_arm: the wound rank of the right arm; right, left: ids held
    def free_with(right_arm: 0, right: nil, left: nil)
      stub_const('Wounds', Struct.new(:rightArm, :rightHand, :leftArm, :leftHand).new(right_arm, 0, 0, 0))
      stub_const('Scars', Struct.new(:rightArm, :rightHand, :leftArm, :leftHand).new(0, 0, 0, 0))
      hands(right: right, left: left)
      stowed = []
      allow(sack).to receive(:waitrt?)
      allow(sack).to receive_messages(checkright: true, checkleft: true)
      allow(sack).to receive(:fput) { |cmd| stowed << cmd }
      sack.free_hand
      stowed
    end

    it 'does nothing when a usable hand is empty' do
      expect(free_with).to be_empty
      expect(free_with(right: '1')).to be_empty
    end

    it 'stows from the right hand when both are full and sound' do
      expect(free_with(right: '1', left: '2')).to eq(['stow right thing'])
    end

    it 'stows from the left hand when the right arm is crippled' do
      expect(free_with(right_arm: 3, right: '1', left: '2')).to eq(['stow left thing'])
    end
  end

  describe '.herb_in_hand and #note' do
    it 'finds a known herb in either hand' do
      stub_const('GameObj', Class.new do
        define_singleton_method(:right_hand) { Struct.new(:name).new('Empty') }
        define_singleton_method(:left_hand) { Struct.new(:name).new('tincture of acantha') }
      end)
      expect(described_class.herb_in_hand.name).to eq('tincture of acantha')
    end

    it 'finds nothing when the hands hold no herb' do
      stub_const('GameObj', Class.new do
        define_singleton_method(:right_hand) { Struct.new(:name).new('silver ring') }
        define_singleton_method(:left_hand) { Struct.new(:name).new(nil) }
      end)
      expect(described_class.herb_in_hand).to be_nil
    end

    it 'finds a bank note in the sack when no hand holds one' do
      note = item.new(id: '30', name: 'bank note', noun: 'note')
      stub_const('GameObj', Class.new do
        define_singleton_method(:right_hand) { Struct.new(:noun).new(nil) }
        define_singleton_method(:left_hand) { Struct.new(:noun).new(nil) }
      end)
      backpack.contents = [acantha, note]
      expect(sack.note).to eq(note)
    end
  end

  describe '#contents' do
    it 'reads a carried sack by what Lich knows is in it' do
      backpack.contents = [acantha, item.new(id: '7', name: 'silver ring', noun: 'ring', type: 'jewelry')]
      inventory(backpack)
      allow(sack).to receive(:open).and_return(:open)
      sack.survival_kit = false
      expect(sack.contents[:all]).to eq([acantha])
    end

    it 'reads a room container from the listing the game gives, keeping only known herbs' do
      bench = item.new(id: '20', name: 'wooden bench', noun: 'bench')
      room_sack = described_class.new(bench, preposition: 'on')
      listing = %(On the <a exist="20" noun="bench">wooden bench</a> you see <a exist="5" noun="tincture">tincture of acantha</a>, ) +
                %(<a exist="9" noun="mug">a pewter mug</a> and <a exist="6" noun="tincture">tincture of aloeas</a>.)
      stub_const('GameObj', Class.new do
        define_singleton_method(:inv) { [] }
        define_singleton_method(:new_inv) { |exist, noun, name, _| Struct.new(:id, :noun, :name, :type).new(exist, noun, name, 'herb') }
      end)
      allow(EO).to receive(:command).and_return([listing])
      expect(room_sack.contents[:all].map(&:name)).to eq(['tincture of acantha', 'tincture of aloeas'])
    end
  end

  describe '#open' do
    def open_with(open_lines: [], look_lines: [], known: false)
      stub_const('EO::Containers', Class.new { define_singleton_method(:closed?) { |_| false } })
      stub_const('GameObj', Class.new { define_singleton_method(:containers) { known ? { '10' => [] } : {} } })
      allow(EO).to receive(:command) { |cmd, *| cmd.start_with?('open') ? open_lines : look_lines }
      allow(sack).to receive(:sleep)
      sack.open
    end

    it 'is open at once when Lich already knows what is inside' do
      expect(open_with(known: true)).to eq(:open)
      expect(EO).not_to have_received(:command)
    end

    it 'remembers to close what it opened' do
      open_with(open_lines: ['You open your backpack.'], look_lines: ['In the backpack you see a ring.'])
      expect(sack.close_after).to be(true)
    end

    it 'does not close what was open already' do
      open_with(open_lines: ['That is already open.'], look_lines: ['In the backpack you see a ring.'])
      expect(sack.close_after).to be(false)
    end

    it 'says so when it is locked, and when there is nothing in it' do
      expect(open_with(open_lines: ['It appears to be locked.'])).to eq(:locked)
      expect(open_with(open_lines: ['You open your backpack.'], look_lines: ['There is nothing in the backpack.'])).to eq(:empty)
    end
  end
end
