# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/containers'
require_relative '../../scripts/eo/hands'
require_relative '../../scripts/eo/town'
require_relative '../../scripts/eo/items'
require_relative '../../scripts/eo/boxes'
require_relative '../../scripts/eo/carry'
require_relative '../../scripts/eo/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/loot/context'
require_relative '../../scripts/eo/loot/floor'

RSpec.describe EO::Loot::Floor do
  let(:thing) { Struct.new(:id, :name, :type, :contents, :noun, keyword_init: true) }
  let(:sack) { thing.new(id: '2', name: 'leather sack', contents: []) }
  let(:ruby) { thing.new(id: '10', name: 'blue ruby', type: 'gem') }
  let(:pearl) { thing.new(id: '11', name: 'pink pearl', type: 'gem') }
  let(:rock) { thing.new(id: '12', name: 'grey rock', type: 'junk') }
  let(:coins) { thing.new(id: '13', name: 'some silver coins', type: nil) }
  let(:cursed) { thing.new(id: '14', name: 'bone ring', type: 'jewelry,cursed') }
  let(:chest) { thing.new(id: '50', name: 'silver chest', type: 'box', contents: []) }
  let(:settings) do
    { loot_types: %w[gem coins], crumbly: [], unlootable: [], sell_loot_types: [], display_box_contents: false }
  end
  let(:said) { [] }
  let(:saved) { [] }
  let(:log) { [] }
  let(:loot_on_floor) { [] }
  let(:right) { thing.new(id: nil, name: 'Empty') }
  let(:left) { thing.new(id: nil, name: 'Empty') }
  let(:drag_answers) { {} }
  let(:command_answers) { {} }
  let(:result_answers) { [] }
  let(:decurse_answer) { true }
  let(:toss_answers) { {} }
  let(:stow) { EO::Stow.new(bags: { default: sack }) }
  let(:context) do
    said_to = said
    saved_to = saved
    EO::Loot::Context.new(settings: settings, stow: stow, loot_exclude_regex: /\bnever\b/, loot_keep_regex: /\bkeeper\b/,
                          allowed_special_types: %w[collectible], look_regex: /look/,
                          say: ->(type:, text:) { said_to << [type, text] }, save: -> { saved_to << true })
  end
  let(:hands) do
    events = log
    answers = drag_answers
    Class.new do
      define_method(:free_hand) { events << [:free_hand] }
      define_method(:free_hands) { |both: false| events << [:free_hands, both] }
      define_method(:single_drag) do |item, phase = true, on_full: nil|
        events << [:single_drag, item.name, phase, on_full]
        answers[item.name]
      end
      define_method(:single_loot) { |item| events << [:single_loot, item.name] }
      define_method(:drag) { |item| events << [:drag, item.name] }
      define_method(:open_loot_containers) { |objs| events << [:open, objs.map(&:name)] }
    end.new
  end
  let(:floor) do
    events = log
    commands = command_answers
    results = result_answers
    tosses = toss_answers
    described_class.new(
      context, hands: hands,
               command: ->(cmd, _regex, **) { events << [:command, cmd]; commands.fetch(cmd, []) },
               result: ->(cmd, _regex = nil) { events << [:result, cmd]; results.shift },
               decurse: ->(item) { events << [:decurse, item.name]; decurse_answer },
               unlootable: ->(item) { events << [:unlootable, item.name] },
               toss: ->(item, cmd, attempts: 1) { events << [:toss, item.name, cmd, attempts]; tosses.fetch(item.name, true) },
               snapshot: -> { events << [:snapshot]; :snapshot }
    )
  end

  before do
    floor_items = loot_on_floor
    hand_pair = [right, left]
    stub_const('GameObj', Module.new do
      define_singleton_method(:loot) { floor_items }
      define_singleton_method(:right_hand) { hand_pair[0] }
      define_singleton_method(:left_hand) { hand_pair[1] }
    end)
    bag = sack
    stub_const('StowList', Module.new { define_singleton_method(:stow_list) { { default: bag } } })
    stub_const('Stats', Module.new { define_singleton_method(:level) { 50 } })
    stub_const('Bounty', Module.new { define_singleton_method(:task) { Struct.new(:heirloom?).new(false) } })
    allow(EO).to receive(:settle)
    allow(EO::Hands).to receive(:holding?).and_return(false)
    allow(EO::Carry).to receive(:observe)
    described_class.send(:define_method, :waitrt?) { nil }
  end

  after { described_class.send(:remove_method, :waitrt?) }

  def loud = said.reject { |type, _| type == 'debug' }

  describe 'what is loot' do
    it 'tells the wanted from the unwanted' do
      expect(floor.valid_objs([ruby, rock])).to eq([ruby])
      expect(floor.invalid_objs([ruby, rock])).to eq([rock])
    end

    it 'does not count what is no loot at all' do
      crater = thing.new(id: '30', name: 'jagged crater', type: nil)
      expect(floor.reject_invalid_loot([ruby, crater])).to eq([ruby])
    end

    it 'takes the bounty heirloom into the policy' do
      task = Struct.new(:heirloom?, :requirements).new(true, { item: 'blue ruby' })
      stub_const('Bounty', Module.new { define_singleton_method(:task) { task } })
      expect(floor.policy.heirloom).to eq('blue ruby')
    end
  end

  describe '#loot_specials' do
    it 'opens the bags loot goes into before it starts' do
      floor.loot_specials([ruby])
      expect(log.first).to eq([:open, ['blue ruby']])
    end

    it 'leaves ordinary items for loot_regular' do
      expect(floor.loot_specials([ruby, rock])).to eq([ruby, rock])
      expect(log.map(&:first)).not_to include(:single_drag)
    end

    it 'gathers coins when coins are chosen, with the charm if there is one' do
      result_answers.push('you gather')
      expect(floor.loot_specials([coins, ruby])).to eq([ruby])
      expect(log).to include([:result, 'get coins'])

      context.charm = thing.new(id: '77', name: 'coin charm')
      result_answers.push('you summon')
      floor.loot_specials([coins])
      expect(log).to include([:result, 'rub #77'])
    end

    it 'leaves coins alone when coins are not chosen' do
      settings[:loot_types] = %w[gem]
      expect(floor.loot_specials([coins])).to eq([coins])
      expect(log.map(&:first)).not_to include(:result)
    end

    it 'drags a cursed item once it can be picked up, and drops it from the list either way' do
      settings[:loot_types] = %w[gem cursed]
      expect(floor.loot_specials([cursed])).to eq([])
      expect(log).to include([:decurse, 'bone ring'], [:free_hand], [:single_drag, 'bone ring', true, nil])
    end

    it 'does not drag a cursed item it could not make safe' do
      settings[:loot_types] = %w[gem cursed]
      allow(floor).to receive(:decurse_answer).and_return(false) if floor.respond_to?(:decurse_answer)
      decurse = ->(item) { log << [:decurse, item.name]; false }
      cautious = described_class.new(context, hands: hands, command: ->(*, **) { [] }, result: ->(*) {}, decurse: decurse,
                                              unlootable: ->(_i) {}, toss: ->(*, **) { true }, snapshot: -> {})
      expect(cautious.loot_specials([cursed])).to eq([])
      expect(log.map(&:first)).not_to include(:single_drag)
    end

    it 'leaves a cursed item when cursed is not chosen' do
      expect(floor.loot_specials([cursed])).to eq([cursed])
    end

    it 'does not take a cursed item because its other type is allowed, unless cursed is chosen' do
      context.allowed_special_types = %w[jewelry]
      expect(floor.loot_specials([cursed])).to eq([cursed])
      settings[:loot_types] << 'cursed'
      expect(floor.loot_specials([cursed])).to eq([])
    end

    it 'takes an uncommon armor only when armor is chosen' do
      plate = thing.new(id: '28', name: 'odd plate', type: 'armor,uncommon')
      expect(floor.loot_specials([plate])).to eq([plate])
      settings[:loot_types] << 'armor'
      expect(floor.loot_specials([plate])).to eq([])
    end

    it "takes the highlands' uncommon items only when uncommon is chosen" do
      quill = thing.new(id: '29', name: 'stygian valravn quill', type: 'junk')
      expect(floor.loot_specials([quill])).to eq([quill])
      settings[:loot_types] << 'uncommon'
      expect(floor.loot_specials([quill])).to eq([])
    end

    it 'takes what the keep list names and the allowed special types' do
      keeper = thing.new(id: '20', name: 'a keeper trinket', type: 'junk')
      relic = thing.new(id: '21', name: 'old relic', type: 'collectible')
      expect(floor.loot_specials([keeper, relic, rock])).to eq([rock])
      expect(log.select { |e| e.first == :single_drag }.map { |e| e[1] }).to eq(['a keeper trinket', 'old relic'])
    end

    it 'does not take what the exclude list names' do
      shunned = thing.new(id: '22', name: 'never relic', type: 'collectible')
      expect(floor.loot_specials([shunned])).to eq([shunned])
    end

    it 'takes an uncommon weapon only when weapons are chosen' do
      blade = thing.new(id: '23', name: 'odd blade', type: 'weapon,uncommon')
      expect(floor.loot_specials([blade])).to eq([blade])
      settings[:loot_types] << 'weapon'
      expect(floor.loot_specials([blade])).to eq([])
    end

    it 'takes a magic orb only when magic is chosen' do
      orb = thing.new(id: '24', name: 'glowing orb', type: 'magic')
      expect(floor.loot_specials([orb])).to eq([orb])
      settings[:loot_types] << 'magic'
      expect(floor.loot_specials([orb])).to eq([])
    end

    it 'leaves oblivion quartz for the ordinary loot, which wants it only at level 100' do
      quartz = thing.new(id: '25', name: 'shard of oblivion quartz', type: 'gem')
      expect(floor.loot_specials([quartz])).to eq([quartz])
    end

    it 'leaves oblivion quartz at level 100 for the ordinary loot even where its type is a special one' do
      stub_const('Stats', Module.new { define_singleton_method(:level) { 100 } })
      context.allowed_special_types = %w[gem]
      quartz = thing.new(id: '25', name: 'shard of oblivion quartz', type: 'gem')
      expect(floor.loot_specials([quartz])).to eq([quartz])
    end

    it 'loots a bag of clothing, and drops what decays on opening' do
      pack = thing.new(id: '26', name: 'tattered pack', type: 'clothing', contents: [])
      command_answers['open #26'] = ['The tattered pack crumbles and decays away']
      expect(floor.loot_specials([pack])).to eq([])
      expect(settings[:crumbly]).to eq(['tattered pack'])
    end

    describe 'in a box' do
      let(:stowed) { [] }
      let(:recovering) do
        events = stowed
        described_class.new(context, hands: hands, command: ->(*, **) { [] }, result: ->(*) {}, decurse: ->(_i) { true },
                                     unlootable: ->(_i) {}, toss: ->(*, **) { true }, snapshot: -> {},
                                     stow_box_item: ->(item, *_rest) { events << item.name; item.name == 'bone ring' ? :recovered : nil })
      end

      before { settings[:loot_types] = %w[gem cursed] }

      it 'puts each item away through the caller, not the hands' do
        stowed_relic = thing.new(id: '21', name: 'old relic', type: 'collectible')
        recovering.loot_specials([stowed_relic], box: chest)
        expect(stowed).to eq(['old relic'])
        expect(log.map(&:first)).not_to include(:single_drag)
      end

      it 'stops and says :recovered when a recovery looted the whole box' do
        late = thing.new(id: '27', name: 'late relic', type: 'collectible')
        expect(recovering.loot_specials([cursed, late], box: chest)).to eq(:recovered)
        expect(stowed).to eq(['bone ring'])
      end

      it 'drags by hand, and again when nothing has room, with no caller to recover' do
        relic = thing.new(id: '21', name: 'old relic', type: 'collectible')
        drag_answers['old relic'] = :full
        floor.loot_specials([relic], box: chest)
        expect(log.select { |e| e.first == :single_drag }).to eq([[:single_drag, 'old relic', true, :signal], [:single_drag, 'old relic', true, nil]])
      end
    end
  end

  describe '#bag_loot' do
    let(:pack) { thing.new(id: '40', name: 'small pack', type: 'clothing', contents: [ruby, rock]) }

    it 'does not open a bag it has been through' do
      context.checked_bags.push('40')
      expect(floor.bag_loot(pack)).to be_nil
      expect(log).to be_empty
    end

    it 'remembers a bag that decays on opening, unless it is one that always does' do
      command_answers['open #40'] = ['The small pack crumbles and decays away.']
      expect(floor.bag_loot(pack)).to eq('crumbly')
      expect(settings[:crumbly]).to eq(['small pack'])
      expect(saved.size).to eq(1)

      bandana = thing.new(id: '41', name: 'red bandana', type: 'clothing', contents: [])
      command_answers['open #41'] = ['The red bandana crumbles and decays away.']
      expect(floor.bag_loot(bandana)).to eq('crumbly')
      expect(settings[:crumbly]).to eq(['small pack'])
    end

    it 'marks a bag the game cannot open as checked' do
      command_answers['open #40'] = ['There doesn\'t seem to be any way to do that.']
      expect(floor.bag_loot(pack)).to be_nil
      expect(context.checked_bags).to eq(['40'])
    end

    it 'says false when the game could not find it on looking in' do
      command_answers['look in #40'] = ['I could not find what you were referring to.']
      expect(floor.bag_loot(pack)).to be(false)
      expect(context.checked_bags).to be_empty
    end

    it 'loots what is in it and marks it checked' do
      floor.bag_loot(pack)
      expect(log).to include([:command, 'open #40'], [:command, 'look in #40'])
      expect(log).to include([:free_hand])
      expect(context.checked_bags).to eq(['40'])
    end

    it 'marks an empty bag checked without looting' do
      pack.contents = []
      floor.bag_loot(pack)
      expect(context.checked_bags).to eq(['40'])
      expect(log.map(&:first)).not_to include(:open)
    end
  end

  describe '#loot_regular' do
    let(:silver) { thing.new(id: '60', name: 'silver coins', type: nil) }

    it 'takes the room\'s wanted loot with LOOT where it can, by hand where it cannot, leaving the rest' do
      settings[:loot_types] = %w[gem junk]
      stew = thing.new(id: '61', name: 'a stew', type: 'food')
      floor.loot_regular([ruby, stew, rock], 'Room')
      expect(log).to include([:single_loot, 'blue ruby'], [:single_drag, 'grey rock', true, nil])
      expect(log).not_to include([:single_drag, 'a stew', true, nil])
      expect(loud).to eq([['info', ' Left the following item: a stew.']])
    end

    it 'loots the whole room at once when everything in it is wanted' do
      command_answers['loot room'] = ['There is no loot']
      floor.loot_regular([ruby, pearl], 'Room')
      expect(log).to include([:free_hand], [:command, 'loot room'], [:unlootable, 'blue ruby'], [:unlootable, 'pink pearl'])
    end

    it 'does not take silver coins from the room when coins are not chosen' do
      settings[:loot_types] = %w[gem]
      loot_on_floor << silver
      floor.loot_regular([ruby, silver], 'Room')
      expect(log.map(&:first)).to include(:single_loot)
      expect(log).not_to include([:single_loot, 'silver coins'])
      expect(log.map { |e| e[1] }).not_to include('silver coins')
      expect(loud.map(&:last)).to eq([' Left the following item: silver coins.'])
    end

    it 'says every item it left, with an s for several' do
      settings[:loot_types] = %w[gem]
      stew = thing.new(id: '61', name: 'a stew', type: 'food')
      floor.loot_regular([ruby, stew, rock], 'Room')
      expect(loud.map(&:last)).to eq([' Left the following items: a stew, grey rock.'])
    end

    it 'drags a bag\'s items one by one' do
      floor.loot_regular([ruby, pearl])
      expect(log.select { |e| e.first == :single_drag }.map { |e| e[1] }).to eq(['blue ruby', 'pink pearl'])
    end

    describe 'from a box' do
      let(:stowed) { [] }
      let(:recovering) do
        events = stowed
        described_class.new(context, hands: hands, command: ->(cmd, *, **) { events << cmd; command_answers.fetch(cmd, []) },
                                     result: ->(*) {}, decurse: ->(_i) { true }, unlootable: ->(_i) {}, toss: ->(*, **) { true },
                                     snapshot: -> {}, stow_box_item: ->(item, *) { events << item.name; item.name == 'pink pearl' ? :recovered : nil })
      end

      it 'puts each wanted item away through the caller when something is left behind' do
        settings[:loot_types] = %w[gem]
        recovering.loot_regular([ruby, rock], 'Box', chest)
        expect(stowed).to eq(['blue ruby'])
      end

      it 'says :recovered, and goes no further, when a recovery looted the box' do
        settings[:loot_types] = %w[gem]
        expect(recovering.loot_regular([pearl, ruby, rock], 'Box', chest)).to eq(:recovered)
        expect(stowed).to eq(['pink pearl'])
      end

      it 'loots the box with LOOT when all of it is wanted, then puts away what stayed in hand and in the box' do
        chest.contents = [ruby]
        right.id = '10'
        right.name = 'blue ruby'
        right.type = 'gem'
        recovering.loot_regular([ruby], 'Box', chest)
        expect(stowed).to eq(['loot #50', 'blue ruby', 'Empty', 'blue ruby'])
        expect(log).to include([:free_hand])
        expect(EO).to have_received(:settle)
      end

      it 'says :recovered when a recovery ran for what was left in hand' do
        right.id = '11'
        right.name = 'pink pearl'
        right.type = 'gem'
        expect(recovering.loot_regular([ruby], 'Box', chest)).to eq(:recovered)
      end

      it 'does not put a box in a hand away as an item of the box' do
        right.id = '50'
        right.name = 'silver chest'
        right.type = 'box'
        chest.contents = []
        recovering.loot_regular([ruby], 'Box', chest)
        expect(stowed).to eq(['loot #50', 'Empty'])
      end

      it 'puts items away without a caller to recover, by hand when nothing has room' do
        settings[:loot_types] = %w[gem]
        drag_answers['blue ruby'] = :full
        floor.loot_regular([ruby, rock], 'Box', chest)
        expect(log.select { |e| e.first == :single_drag }).to eq([[:single_drag, 'blue ruby', true, :signal], [:single_drag, 'blue ruby', true, nil]])
      end
    end
  end

  describe '#room_regular_steps' do
    it 'is one action for each wanted item when some of the room is left, the first freeing a hand' do
      steps = floor.room_regular_steps([ruby, pearl, rock])
      expect(steps.size).to eq(2)
      steps.each(&:call)
      expect(log.map(&:first)).to eq(%i[free_hand single_loot single_loot])
    end

    it 'is a single LOOT ROOM when all of it is wanted' do
      command_answers['loot room'] = ['There is no loot']
      steps = floor.room_regular_steps([ruby, pearl])
      expect(steps.size).to eq(1)
      expect(log).to be_empty
      steps.each(&:call)
      expect(log).to include([:command, 'loot room'])
    end

    it 'is only the report when nothing is wanted, and says what was left in the last action' do
      steps = floor.room_regular_steps([rock])
      expect(steps.size).to eq(1)
      steps.first.call
      expect(loud).to eq([['info', ' Left the following item: grey rock.']])
    end

    it 'says nothing is left when all of it was looted' do
      steps = floor.room_regular_steps([ruby])
      steps.each(&:call)
      expect(loud).to be_empty
    end
  end

  describe '#special' do
    it 'is false for an ordinary item and does nothing with it' do
      expect(floor.special(ruby)).to be(false)
      expect(log).to be_empty
    end

    it 'is true for an item it took' do
      relic = thing.new(id: '21', name: 'old relic', type: 'collectible')
      expect(floor.special(relic)).to be(true)
    end

    it 'is :recovered when a recovery looted the box' do
      recovering = described_class.new(context, hands: hands, command: ->(*, **) { [] }, result: ->(*) {}, decurse: ->(_i) { true },
                                                unlootable: ->(_i) {}, toss: ->(*, **) { true }, snapshot: -> {},
                                                stow_box_item: ->(*) { :recovered })
      relic = thing.new(id: '21', name: 'old relic', type: 'collectible')
      expect(recovering.special(relic, box: chest)).to eq(:recovered)
    end
  end

  describe '#room_candidates and #open_bags' do
    it 'weighs the room only when it holds loot' do
      expect(floor.room_candidates).to eq([])
      expect(log).to be_empty
      loot_on_floor << ruby
      expect(floor.room_candidates).to eq([ruby])
      expect(log).to eq([[:snapshot]])
    end

    it 'opens the bags loot goes into' do
      floor.open_bags([ruby])
      expect(log).to eq([[:open, ['blue ruby']]])
    end

    it 'forgets the weights' do
      allow(stow).to receive(:observe)
      floor.forget_weights
      expect(stow).to have_received(:observe).with(nil)
    end
  end

  describe '#loot_all' do
    it 'asks for the unlootable list to be added to when the game says there is no loot' do
      command_answers['loot room'] = ['There is no loot here.']
      expect(floor.loot_all([ruby])).to be(true)
      expect(log).to include([:unlootable, 'blue ruby'])
    end

    it 'learns a bag that closed itself, once, when LOOT ROOM found it closed' do
      command_answers['loot room'] = ["You can't put it away. It's closed!"]
      command_answers['look in #2'] = ['That is closed.']
      allow(stow).to receive(:closes_itself?).and_return(true)
      allow(stow).to receive(:learn)
      floor.loot_all([ruby, pearl])
      expect(stow).to have_received(:learn).with(:auto_close, sack).once
      expect(log.count { |e| e == [:command, 'look in #2'] }).to eq(1)
    end

    it 'does not look in a bag that does not close itself' do
      command_answers['loot room'] = ["You can't put it away. It's closed!"]
      allow(stow).to receive(:closes_itself?).and_return(false)
      floor.loot_all([ruby])
      expect(log).not_to include([:command, 'look in #2'])
    end

    it 'puts away only what is in hand that it was looting' do
      command_answers['loot room'] = ['You gather up and stow what treasure you can manage']
      right.id = '99'
      right.name = 'borrowed knife'
      allow(floor).to receive(:room)
      floor.loot_all([ruby])
      expect(log.map(&:first)).not_to include(:single_drag)
    end

    it 'puts away what is left in a hand and loots the room again if anything remains' do
      command_answers['loot room'] = ['You gather up and stow what treasure you can manage']
      right.id = '10'
      right.name = 'blue ruby'
      loot_on_floor << pearl
      reruns = []
      allow(floor).to receive(:room) { reruns << :room }
      floor.loot_all([ruby])
      expect(log).to include([:single_drag, 'blue ruby', true, nil])
      expect(reruns).to eq([:room])
    end

    it 'does not loot the room again when nothing remains' do
      command_answers['loot room'] = ['You gather up and stow what treasure you can manage']
      allow(floor).to receive(:room)
      floor.loot_all([ruby])
      expect(floor).not_to have_received(:room)
    end
  end

  describe '#room' do
    it 'weighs the room, takes the specials and then the ordinary loot' do
      loot_on_floor.push(ruby, rock)
      command_answers['loot room'] = []
      floor.room
      expect(log.first).to eq([:snapshot])
      expect(log.map(&:first)).to include(:open)
    end

    it 'passes the snapshot to the stow and to what learns the encumbrance' do
      loot_on_floor << ruby
      allow(stow).to receive(:observe)
      floor.room
      expect(stow).to have_received(:observe).with(:snapshot)
      expect(EO::Carry).to have_received(:observe).with(:snapshot)
    end

    it 'forgets the weights when the pass ends, whatever happened' do
      loot_on_floor << ruby
      allow(stow).to receive(:observe)
      allow(floor).to receive(:weigh_room)
      allow(floor).to receive(:loot_specials).and_raise('boom')
      expect { floor.room }.to raise_error('boom')
      expect(stow).to have_received(:observe).with(nil).once
    end

    it 'does nothing for a room with no loot' do
      floor.room
      expect(log).to be_empty
    end

    it 'goes without weights when the snapshot cannot be taken' do
      loot_on_floor << ruby
      quiet = described_class.new(context, hands: hands, command: ->(*, **) { [] }, result: ->(*) {}, decurse: ->(_i) { true },
                                           unlootable: ->(_i) {}, toss: ->(*, **) { true }, snapshot: -> {})
      allow(stow).to receive(:observe)
      quiet.room
      expect(stow).not_to have_received(:observe).with(:snapshot)
      expect(EO::Carry).not_to have_received(:observe)
    end

    it 'says what went wrong with the snapshot and goes on' do
      broken = described_class.new(context, hands: hands, command: ->(*, **) { [] }, result: ->(*) {}, decurse: ->(_i) { true },
                                            unlootable: ->(_i) {}, toss: ->(*, **) { true }, snapshot: -> { raise 'feed down' })
      broken.weigh_room
      expect(said).to include(['debug', 'weigh_room: feed down'])
    end
  end

  describe '#box_loot_ground' do
    let(:valuable) { thing.new(id: '51', name: 'gold chest', type: 'box', contents: []) }

    before do
      loot_on_floor << chest
      allow(EO::Boxes).to receive(:open).and_return(:open)
      allow(EO::Boxes).to receive(:coins).and_return([:ok, 0])
      allow(EO::Town).to receive(:trash_can).and_return(thing.new(id: '90', name: 'barrel'))
      settings[:sell_loot_types] = []
    end

    it 'frees both hands first' do
      floor.box_loot_ground
      expect(log.first).to eq([:free_hands, true])
    end

    it 'skips a locked box and one whose contents it cannot see, saying so for the second' do
      allow(EO::Boxes).to receive(:open).and_return(:locked)
      floor.box_loot_ground
      expect(log.map(&:first)).not_to include(:drag)

      allow(EO::Boxes).to receive(:open).and_return(:unknown)
      floor.box_loot_ground
      expect(loud.map(&:last)).to eq([' Unable to determine the contents of  silver chest.'])
    end

    it 'takes the box in hand, gets its coins, loots it and throws it away' do
      floor.box_loot_ground
      expect(log).to include([:drag, 'silver chest'], [:toss, 'silver chest', 'trash', 4])
    end

    it 'drops the box where there is no trash can' do
      allow(EO::Town).to receive(:trash_can).and_return(nil)
      floor.box_loot_ground
      expect(log).to include([:toss, 'silver chest', 'drop', 4])
    end

    it 'says :coins_full and goes no further when the character cannot hold the coins' do
      allow(EO::Boxes).to receive(:coins).and_return([:full, 0])
      expect(floor.box_loot_ground).to eq(:coins_full)
      expect(loud.map(&:last)).to eq([" Can't hold any more coins...Exiting!"])
      expect(log.map(&:first)).not_to include(:toss)
    end

    it 'leaves the coins, saying so, when the answer is not known' do
      allow(EO::Boxes).to receive(:coins).and_return([:unknown, 0])
      floor.box_loot_ground
      expect(loud.map(&:last)).to include(' Unknown get coin result, leaving the coins.')
    end

    it 'keeps an empty valuable box when box is a type to save' do
      loot_on_floor.replace([valuable])
      settings[:sell_loot_types] = %w[box]
      floor.box_loot_ground
      expect(log).to include([:single_drag, 'gold chest', false, nil])
      expect(log.map(&:first)).not_to include(:toss)
    end

    it 'tosses the items of a valuable box one by one, keeping what will not go' do
      valuable.contents = [ruby, rock]
      loot_on_floor.replace([valuable])
      settings[:sell_loot_types] = %w[box]
      settings[:loot_types] = []
      toss_answers['grey rock'] = false
      floor.box_loot_ground
      expect(log).to include([:toss, 'blue ruby', 'trash', 1], [:toss, 'grey rock', 'trash', 1], [:single_drag, 'grey rock', true, nil])
      expect(log).not_to include([:toss, 'gold chest', 'trash', 4])
    end

    it 'throws a valuable box away whole when something in it is cursed' do
      valuable.contents = [cursed]
      loot_on_floor.replace([valuable])
      settings[:sell_loot_types] = %w[box]
      settings[:loot_types] = []
      floor.box_loot_ground
      expect(log).to include([:toss, 'gold chest', 'trash', 4])
      expect(log).not_to include([:toss, 'bone ring', 'trash', 1])
    end

    it 'puts the box away when it would not be thrown' do
      allow(EO::Hands).to receive(:holding?).with(chest).and_return(true)
      floor.box_loot_ground
      expect(log).to include([:single_drag, 'silver chest', false, nil])
    end
  end
end
