# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/locker'
require_relative '../../scripts/eo/hoard'

RSpec.describe EO::Locker do
  include_context 'a script lending helpers'

  let(:room_type) do
    Struct.new(:id, :tags, :location, :town, :wayto, keyword_init: true) do
      def find_nearest_by_tag(_tag) = town
    end
  end
  let(:obj) { Struct.new(:id, :noun, :name, :contents, keyword_init: true) }
  let(:loot) { [] }
  let(:room_desc) { [] }

  before do
    floor = loot
    desc = room_desc
    stub_const('GameObj', Class.new do
      define_singleton_method(:loot) { floor }
      define_singleton_method(:room_desc) { desc }
    end)
  end

  it "finds a house's lockers in a town, or the entrances when no locker is mapped" do
    booth = room_type.new(id: 1, tags: ['meta:che:Sylvanfair:locker'], town: 10)
    door = room_type.new(id: 2, tags: ['meta:che:Sylvanfair:entrance_locker'], town: 10)
    other = room_type.new(id: 3, tags: ['meta:che:Sylvanfair:entrance_locker'], town: 20)
    expect(described_class.che_rooms([booth, door, other], 'Sylvanfair', 10)).to eq([booth])
    expect(described_class.che_rooms([door, other], 'Sylvanfair', 10)).to eq([door])
    expect(described_class.che_rooms([booth], 'none', 10)).to eq([])
  end

  it 'gives a place one name however the game and the map write it' do
    expect(described_class.town_name("the town of Kraken's Fall")).to eq("kraken's fall")
    expect(described_class.town_name('Teras Isle')).to eq('kharam-dzu')
    expect(described_class.town_name('the Isle of Four Winds')).to eq('mist harbor')
    expect(described_class.town_name('the Lost Home')).to eq("ta'illistim")
  end

  it "finds the town of a house's lockers by the name LOCKER INFO gives" do
    booth = room_type.new(id: 1, tags: ['meta:che:Sylvanfair:locker'], location: 'Kharam-Dzu', town: 30)
    expect(described_class.che_town_id([booth], 'Sylvanfair', 'Teras Isle')).to eq(30)
    expect(described_class.che_town_id([booth], 'Sylvanfair', 'Solhaven')).to be_nil
    expect(described_class.che_town_id([booth], '', 'Teras Isle')).to be_nil
  end

  it 'reads the town out of LOCKER INFO' do
    answers['locker info'] = ["Your locker is currently located in the town of Kraken's Fall."]
    expect(described_class.info_town).to eq("the town of Kraken's Fall")
  end

  it 'keeps only the lines that came after an earlier reading' do
    expect(described_class.lines_since(%w[a b c], %w[b c d e])).to eq(%w[d e])
    expect(described_class.lines_since(%w[a b], %w[x y])).to eq(%w[x y])
  end

  it 'sorts rooms nearest first and drops the ones that cannot be reached' do
    near = room_type.new(id: 1)
    far = room_type.new(id: 2)
    cut_off = room_type.new(id: 3)
    stub_const('Room', Class.new { define_singleton_method(:current) { Struct.new(:dijkstra).new([{}, { 1 => 5, 2 => 40 }]) } })
    expect(described_class.nearest_first([far, cut_off, near])).to eq([near, far])
  end

  it 'goes through an opening or curtain, and calls a tapestry an opening' do
    expect(described_class.way).to be_nil
    loot << obj.new(noun: 'curtain')
    expect(described_class.way).to eq('go curtain')
    loot.replace([obj.new(noun: 'tapestry')])
    expect(described_class.way).to eq('go opening')
  end

  it 'knows a locker room by a locker or counter in it, and a booth by its tag' do
    expect(described_class.inside?).to be(false)
    room_desc << obj.new(name: 'a wooden counter')
    expect(described_class.inside?).to be(true)
    expect(described_class.booth?(room_type.new(tags: ['meta:che:Sylvanfair:locker']))).to be(true)
    expect(described_class.booth?(room_type.new(tags: ['meta:che:Sylvanfair:entrance_locker']))).to be(false)
  end

  it 'finds the room before a booth and the move into it' do
    booth = room_type.new(id: 7)
    outside = room_type.new(id: 6, wayto: { '7' => 'go curtain' })
    stub_const('Room', Class.new do
      define_singleton_method(:current) { Class.new { def dijkstra(_to) = [{ 7 => 6 }, {}] }.new }
      define_singleton_method(:[]) { |_id| outside }
    end)
    expect(described_class.approach(booth)).to eq([6, 'go curtain'])
  end

  it 'reads a debt out of WEALTH' do
    answers['wealth quiet'] = ['You have no silver with you.', 'In the back of your mind you remember you owe a debt of 1,500 silver.']
    expect(described_class.debt).to eq(1500)
    answers['wealth quiet'] = ['You have no silver with you.']
    expect(described_class.debt).to be_nil
  end

  it 'finds the stash on the floor, else on the counter after looking on it' do
    chest = obj.new(id: '4', name: 'a deep chest')
    loot << chest
    expect(described_class.stash('chest')).to equal(chest)
    loot.clear
    room_desc << obj.new(id: '8', name: 'counter', contents: [chest])
    expect(described_class.stash('chest')).to equal(chest)
    expect(sent).to eq(['look on #8'])
  end
end

RSpec.describe EO::Hoard do
  include_context 'a script lending helpers'

  let(:obj) { Struct.new(:id, :noun, :after_name, :contents, keyword_init: true) }

  before do
    stub_const('GameObj', Class.new do
      define_singleton_method(:type_data) do
        { 'gem'     => { name: /ruby|diamond|emerald/, noun: /ruby|diamond|emerald/, exclusion: /fake/ },
          'reagent' => { name: /crystal core/, noun: /core/, exclusion: /fake/ } }
      end
      define_singleton_method(:load_data) { nil }
    end)
    stub_const('Room', Class.new { define_singleton_method(:list) { [] } })
  end

  it 'brings a label and a loose item to one plain, singular name' do
    expect(described_class.normalize('containing blue rubies')).to eq('blue ruby')
    expect(described_class.normalize('some small uncut diamonds')).to eq('uncut diamond')
    expect(described_class.normalize('a handful of polished black onyxes')).to eq('black onyx')
    expect(described_class.normalize('essences of fire')).to eq('essence of fire')
    expect(described_class.normalize('some golden seeds')).to eq('tiny golden seed')
    expect(described_class.normalize(nil)).to be_nil
  end

  it 'tells whether a name is of the kind hoarded' do
    expect(described_class.kind?('blue ruby', 'gem')).to be(true)
    expect(described_class.kind?('fake ruby', 'gem')).to be(false)
    expect(described_class.kind?('crystal core', 'alchemy')).to be(true)
    expect(described_class.kind?('faintly glimmering dust', 'alchemy')).to be(true)
    expect(described_class.kind?('fiery ruby talon', 'gem')).to be(true)
    expect(described_class.kind?('wooden spoon', 'gem')).to be(false)
  end

  it 'filters an inventory by a phrase, whatever the case and spacing' do
    entries = [{ item: 'uncut diamond' }, { item: 'blue diamond' }, { item: 'blue ruby' }]
    expect(described_class.filter(entries, 'Diamond').size).to eq(2)
    expect(described_class.filter(entries, ' uncut  diamond ')).to eq([entries.first])
    expect(described_class.filter(entries, nil)).to eq(entries)
  end

  describe 'a stash of jars' do
    let(:rubies) { obj.new(id: '11', noun: 'jar', after_name: 'containing blue rubies') }
    let(:spoons) { obj.new(id: '12', noun: 'bottle', after_name: 'containing wooden spoons') }
    let(:stash) { obj.new(id: '4', contents: [rubies, obj.new(id: '13', noun: 'jar'), spoons, obj.new(id: '14', noun: 'cloak')]) }

    it 'reads each labelled jar and keeps what is of the kind, with the empty jars counted' do
      answers['look in #11 from #4'] = ['Inside the jar you see 37 portions of blue ruby.  It is full.']
      answers['look in #12 from #4'] = ['Inside the bottle you see 3 portions of wooden spoon.']
      progress = []
      inventory = described_class.inventory(stash, 'gem') { |percent| progress << percent }
      expect(inventory).to eq([{ item: described_class::EMPTY_JARS, count: 1, full: '  -' }, { item: 'blue ruby', count: 37, full: true }])
      expect(progress).to eq([50.0, 100.0])
      expect(sent.first).to eq('look in #4')
    end

    it 'finds the jar labelled with a name' do
      expect(described_class.jar_of(stash, 'blue ruby')).to equal(rubies)
      expect(described_class.jar_of(stash, 'emerald')).to be_nil
    end

    it 'reads a jar in hand as holding some, or as empty' do
      answers['look in #11'] = [['Inside the jar you see 2 portions of blue ruby.'], ['The <a exist="11" noun="jar">jar</a> is empty.'], ['Huh?']]
      expect(described_class.read_jar(rubies)).to eq([2, false])
      expect(described_class.read_jar(rubies)).to eq(:empty)
      expect(described_class.read_jar(rubies)).to be_nil
    end
  end

  describe 'a premium locker' do
    let(:manifest) do
      ['Thinking back, you recall the contents of your locker:', 'In the deep chest:', '  a glass jar containing blue rubies (37/100)',
       '  a glass jar', '  a glass bottle containing wooden spoons (3/50)', '  a glass jar containing uncut diamonds (100/100) (registered)', '',
       'On the weapon rack:', '  a sword']
    end

    it 'names the town a manifest is had for' do
      expect(described_class.manifest_town('deep chest', 'Kharam-Dzu')).to eq('Teras Isle')
      expect(described_class.manifest_town('oak trunk', 'Solhaven')).to eq('Family Vault')
      expect(described_class.manifest_town('deep chest', 'the Hinterwilds')).to be_nil
    end

    it "reads the stash's part of the manifest" do
      answers['locker manifest Solhaven'] = manifest
      expect(described_class.manifest_inventory('Solhaven', 'deep chest', 'gem')).to eq(
        [{ item: described_class::EMPTY_JARS, count: 1, full: '  -' }, { item: 'blue ruby', count: 37, full: false },
         { item: 'uncut diamond', count: 100, full: true }]
      )
    end

    it 'has none when the manifest has no part for the container' do
      answers['locker manifest Solhaven'] = manifest
      expect(described_class.manifest_inventory('Solhaven', 'clothing wardrobe', 'gem')).to be_nil
    end
  end

  it 'shakes one item out of a jar and says when it was the last' do
    jar = obj.new(id: '11', noun: 'jar')
    ruby = obj.new(id: '90', noun: 'ruby')
    stub_const('GameObj', Class.new do
      define_singleton_method(:right_hand) { jar }
      define_singleton_method(:left_hand) { ruby }
    end)
    answers['shake #11'] = ['You give your jar a hard shake.  That was the last of them.']
    expect(described_class.shake(jar)).to eq([ruby, true])
    expect(described_class.jar_in_hand).to equal(jar)
  end
end
