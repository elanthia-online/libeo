# frozen_string_literal: true

require 'prism'
require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/inventory/containers'
require_relative '../../scripts/eo/inventory/hands'
require_relative '../../scripts/eo/inventory/items'
require_relative '../../scripts/eo/inventory/carry'
require_relative '../../scripts/eo/inventory/stow'
require_relative '../../scripts/eo/loot'
require_relative '../../scripts/eo/loot/context'
require_relative '../../scripts/eo/loot/hooks'

# libeo's hooks are copies of eloot's. Each case runs eloot's real method, read
# from eloot.lic, and libeo's hook against the same stand-in game, and asks that
# they send the same commands, say the same things and answer the same.
HOOK_SOURCES = begin
  names = %i[get_command get_res decurse toss unlootable change_stance wait_for_disk disk_contents get_weapon_inv
             find_bloodtooth check_inventory]
  found = {}
  walk = lambda do |node|
    found[node.name] ||= node.slice if node.is_a?(Prism::DefNode) && names.include?(node.name)
    node.compact_child_nodes.each { |c| walk.call(c) if c }
  end
  walk.call(Prism.parse(File.read(File.expand_path('../../scripts/eloot.lic', __dir__))).value)
  found
end

RSpec.describe EO::Loot::Hooks do
  let(:item) { Struct.new(:id, :name, :type, :noun, :contents, :status, keyword_init: true) }
  let(:settings) { { loot_types: %w[gem cursed], sell_container: %w[gem], use_disk: false, log_unlootables: true, unlootable: [] } }

  # One run of the stand-in game: answers handed out in turn, and what was sent.
  def game(answers)
    log = { sent: [], said: [], saved: 0, opened: [] }
    queue = answers.dup
    issue = Module.new
    issue.define_singleton_method(:issue_command) { |cmd, _re, **opts| log[:sent] << [cmd, opts.slice(:silent, :quiet)]; queue.shift || [] }
    stub_const('Lich::Util', issue)
    timeout = ->(cmd, _t, _re) { log[:sent] << [cmd, {}]; queue.shift }
    allow(EO).to receive(:settle) { log[:sent] << [:settle, {}] }
    [log, timeout]
  end

  def context_for(log, s = settings.dup)
    EO::Loot::Context.new(settings: s, say: ->(type:, text:) { log[:said] << [type, text] }, save: -> { log[:saved] += 1 })
  end

  def eloot(context, log, timeout)
    mod = Module.new
    mod.define_singleton_method(:data) { context }
    mod.define_singleton_method(:msg) { |type: 'yellow', text: '', **| log[:said] << [type, text] }
    mod.define_singleton_method(:save_profile) { |**| log[:saved] += 1 }
    mod.define_singleton_method(:room_checkpoint!) { |_e = nil| nil }
    mod.define_singleton_method(:dothistimeout) { |*args| timeout.call(*args) }
    mod.define_singleton_method(:checkright) { false }
    mod.define_singleton_method(:checkleft) { false }
    opener = Object.new
    opener.define_singleton_method(:open_single_container) { |bag| log[:opened] << bag.name }
    mod.const_set(:ELoot, mod)
    mod.const_set(:Inventory, opener)
    HOOK_SOURCES.each_value { |src| mod.module_eval(src.start_with?('def self.') ? src : "def self.#{src.sub('def ', '')}") }
    mod
  end

  def libeo(log, timeout)
    EO::Loot::Hooks.define_singleton_method(:dothistimeout) { |*args| timeout.call(*args) }
    EO::Loot::Hooks.define_singleton_method(:checkright) { false }
    EO::Loot::Hooks.define_singleton_method(:checkleft) { false }
    opener = Object.new
    opener.define_singleton_method(:open_single_container) { |bag| log[:opened] << bag.name }
    opener
  end

  after do
    %i[dothistimeout checkright checkleft].each do |m|
      EO::Loot::Hooks.singleton_class.remove_method(m) if EO::Loot::Hooks.singleton_methods.include?(m)
    end
  end

  # Run eloot's and libeo's on the same answers; both must leave the same trace.
  def both(answers, configure: nil)
    runs = %i[eloot libeo].map do |side|
      log, timeout = game(answers)
      context = context_for(log)
      configure&.call(context)
      result = if side == :eloot
                 yield(:eloot, eloot(context, log, timeout), context)
               else
                 opener = libeo(log, timeout)
                 yield(:libeo, opener, context)
               end
      [result, log, context]
    end
    [runs[0], runs[1]]
  end

  def expect_same((a_result, a_log, _), (b_result, b_log, _))
    expect(b_result).to eq(a_result)
    # eloot logs a bare debug line on entering some; debug is not what the player sees
    plain = ->(log) { log.merge(said: log[:said].reject { |type, _| type == 'debug' }) }
    expect(plain.call(b_log)).to eq(plain.call(a_log))
  end

  describe 'command' do
    it 'sends again after a wait, and answers the lines' do
      e, l = both([['...wait 2 seconds.'], ['You glance.']]) do |side, mod, ctx|
        side == :eloot ? mod.get_command('look', /glance/) : EO::Loot::Hooks.command(ctx).call('look', /glance/)
      end
      expect_same(e, l)
      expect(l[0]).to eq(['You glance.'])
    end

    it 'sends again after a Roundtime line too, as eloot does' do
      e, l = both([['You search.', 'Roundtime: 3 sec.'], ['ok']]) do |side, mod, ctx|
        side == :eloot ? mod.get_command('search', /search/) : EO::Loot::Hooks.command(ctx).call('search', /search/)
      end
      expect_same(e, l)
      expect(l[1][:sent].count { |cmd, _| cmd == 'search' }).to eq(2)
    end

    it 'shows the command and its answer when debugging' do
      e, l = both([['ok']], configure: ->(ctx) { ctx.settings[:debug] = true }) do |side, mod, ctx|
        side == :eloot ? mod.get_command('look', /ok/, silent: true, quiet: true) : EO::Loot::Hooks.command(ctx).call('look', /ok/, silent: true, quiet: true)
      end
      expect_same(e, l)
      expect(l[1][:sent].first).to eq(['look', { silent: nil, quiet: false }])
    end
  end

  describe 'result' do
    it 'sends again after a wait or the rash, and answers the line' do
      answers = ['Wait 3 sec.', 'An uncontrollable urge to scratch the rash', 'You gather the coins.']
      e, l = both(answers) do |side, mod, ctx|
        side == :eloot ? mod.get_res('get coins', /gather/) : EO::Loot::Hooks.result(ctx).call('get coins', /gather/)
      end
      expect_same(e, l)
      expect(l[0]).to eq('You gather the coins.')
    end

    it 'takes any line without a pattern' do
      e, l = both(['Something.']) do |side, mod, ctx|
        side == :eloot ? mod.get_res('look') : EO::Loot::Hooks.result(ctx).call('look')
      end
      expect_same(e, l)
    end
  end

  describe 'decurse' do
    %i[clean cast gauntlet no_mana other].each do |outcome|
      it "answers as eloot does when the decurse says #{outcome}" do
        allow(EO::Items).to receive(:decurse).and_return(outcome)
        ring = item.new(id: '1', name: 'bone ring', type: 'jewelry,cursed')
        e, l = both([]) { |side, mod, ctx| side == :eloot ? mod.decurse(ring) : EO::Loot::Hooks.decurse(ctx).call(ring) }
        expect_same(e, l)
      end
    end

    it 'lets a clean item through, and leaves a cursed one when cursed is not chosen' do
      clean = item.new(id: '2', name: 'ruby', type: 'gem')
      ring = item.new(id: '1', name: 'bone ring', type: 'jewelry,cursed')
      [clean, ring].each do |obj|
        e, l = both([], configure: ->(ctx) { ctx.settings[:loot_types] = %w[gem] }) do |side, mod, ctx|
          side == :eloot ? mod.decurse(obj) : EO::Loot::Hooks.decurse(ctx).call(obj)
        end
        expect_same(e, l)
      end
    end
  end

  describe 'toss' do
    %i[tossed marked kept].each do |outcome|
      it "answers as eloot does when the toss says #{outcome}" do
        allow(EO::Items).to receive(:toss).and_return(outcome)
        rock = item.new(id: '3', name: 'rock')
        e, l = both([]) do |side, mod, ctx|
          side == :eloot ? mod.toss(rock, 'trash', notify_on_keep: true) : EO::Loot::Hooks.toss(ctx).call(rock, 'trash', notify_on_keep: true)
        end
        expect_same(e, l)
        e, l = both([]) { |side, mod, ctx| side == :eloot ? mod.toss(rock, 'drop') : EO::Loot::Hooks.toss(ctx).call(rock, 'drop') }
        expect_same(e, l)
      end
    end
  end

  describe 'unlootable' do
    [[true, nil], [true, 'gem'], [false, nil]].each do |logged, type|
      it "keeps the list as eloot does (logging #{logged}, type #{type.inspect})" do
        rock = item.new(id: '3', name: 'rock', type: type)
        e, l = both([], configure: ->(ctx) { ctx.settings[:log_unlootables] = logged }) do |side, mod, ctx|
          side == :eloot ? mod.unlootable(rock) : EO::Loot::Hooks.unlootable(ctx).call(rock)
          ctx.settings[:unlootable]
        end
        expect_same(e, l)
      end
    end
  end

  describe 'stance' do
    before do
      changed = []
      stub_const('Stance', Module.new do
        const_set(:NAMES, %w[offensive guarded defensive])
        define_singleton_method(:change) { |name| changed << name }
        define_singleton_method(:changed) { changed }
      end)
    end

    [['guarded', false], ['none', false], ['guarded', true]].each do |name, frenzy|
      it "changes as eloot does (#{name}, frenzy #{frenzy})" do
        debuffs = Module.new { define_singleton_method(:active?) { |_n| frenzy } }
        stub_const('Effects', Module.new { const_set(:Debuffs, debuffs) })
        e, l = both([]) do |side, mod, ctx|
          side == :eloot ? mod.change_stance(name) : EO::Loot::Hooks.stance(ctx).call(name)
          Stance.changed.dup.tap { Stance.changed.clear }
        end
        expect_same(e, l)
      end
    end
  end

  describe 'inventory' do
    it 'reads the sell containers and the disk, past what is set aside, as eloot does' do
      gems = item.new(id: '30', name: 'gem pouch', contents: [item.new(id: '7', name: 'ruby'), item.new(id: '8', name: 'pearl')])
      junk = item.new(id: '31', name: 'junk sack', contents: [item.new(id: '9', name: 'rock')])
      disk = item.new(id: '60', name: 'Nisugi disk', status: '')
      list = { gem: gems, junk: junk, default: nil }
      stub_const('StowList', Module.new { define_singleton_method(:stow_list) { list } })
      stub_const('Disk', Module.new { define_singleton_method(:mine) { disk } })
      allow(EO::Items::Disk).to receive(:mine).and_return(disk)
      allow(EO::Items::Disk).to receive(:wait).and_return(disk)
      allow(EO::Containers).to receive(:fresh_contents).and_return([item.new(id: '50', name: 'chest')])
      $sell_ignore = ['8']
      e, l = both([], configure: lambda { |ctx|
        ctx.settings[:use_disk] = true
        ctx.disk = disk
      }) do |side, mod, ctx|
        if side == :eloot
          mod.check_inventory.map(&:id)
        else
          EO::Loot::Hooks.inventory(ctx, mod).call.map(&:id)
        end
      end
      expect_same(e, l)
      expect(l[0]).to eq(%w[7 50])
    ensure
      $sell_ignore = nil
    end
  end

  describe 'what the character carries' do
    let(:game_obj) do
      Class.new do
        attr_reader :id, :noun, :name

        def initialize(id, noun, name)
          @id = id
          @noun = noun
          @name = name
        end
      end
    end

    it 'finds the weapons worn as eloot does' do
      stub_const('GameObj', game_obj)
      line = 'You are currently wearing: <a exist="11" noun="knife">a skinning knife</a> and <a exist="12" noun="club">a bone club</a>.'
      e, l = both([[line]]) do |side, mod, ctx|
        if side == :eloot
          ctx.weapon_inv = []
          mod.get_weapon_inv
          ctx.weapon_inv.map(&:name)
        else
          EO::Loot::Hooks.weapons(EO::Loot::Hooks.command(ctx)).map(&:name)
        end
      end
      expect_same(e, l)
      expect(l[0]).to eq(['a skinning knife', 'a bone club'])
    end

    [true, false].each do |with_bracer|
      it "finds the blood band as eloot does (bracer #{with_bracer})" do
        band = game_obj.new('20', 'bands', 'bloodtooth bands')
        bracer = game_obj.new('21', 'bracer', 'bloodtooth bracer')
        inv = with_bracer ? [band, bracer] : [band]
        stub_const('GameObj', game_obj)
        game_obj.define_singleton_method(:inv) { inv }
        drains = ['It magically drains some of your blood.']
        e, l = both(inv.map { drains }, configure: ->(ctx) { ctx.settings[:use_bloodbands] = true }) do |side, mod, ctx|
          side == :eloot ? mod.find_bloodtooth : EO::Loot::Hooks.find_blood_band(ctx, EO::Loot::Hooks.command(ctx))
          [ctx.blood_band&.name, ctx.settings[:use_bloodbands]]
        end
        expect_same(e, l)
      end
    end
  end
end

RSpec.describe EO::Loot, '.build' do
  let(:obj) { Struct.new(:id, :name, :noun) }
  let(:charm) { obj.new('40', 'fossil charm') }
  let(:gauntlet) { obj.new('41', 'eonake gauntlet') }
  let(:settings) { { loot_types: %w[gem], charm_name: 'fossil charm', use_disk: true, skin_enable: true } }

  before do
    require_relative '../../scripts/eo/loot/pickup'
    require_relative '../../scripts/eo/loot/floor'
    require_relative '../../scripts/eo/loot/pass'
    require_relative '../../scripts/eo/loot/handler'
    require_relative '../../scripts/eo/skinning'
    require_relative '../../scripts/eo/skinning/pass'
    inv = [charm, gauntlet]
    empty = obj.new(nil, 'Empty')
    stub_const('GameObj', Class.new do
      define_singleton_method(:inv) { inv }
      define_singleton_method(:dead) { [] }
      define_singleton_method(:right_hand) { empty }
      define_singleton_method(:left_hand) { empty }
    end)
    stub_const('Group', Module.new { define_singleton_method(:disks) { [Struct.new(:name).new('Nisugi'), Struct.new(:name).new('Ann')] } })
    stub_const('ReadyList', Module.new { const_set(:ORIGINAL_READY_LIST, []) })
    stub_const('EO::Hands::PUT', /put/)
    stub_const('EO::Containers::LOOK', /look/)
    allow(EO::Items::Disk).to receive(:mine).and_return(:my_disk)
    allow(EO::Loot::Hooks).to receive(:weapons).and_return([:knife])
  end

  let(:pass) { described_class.build(settings, say: ->(**) {}) }
  let(:context) { pass.instance_variable_get(:@context) }

  it 'is a pass ready to run' do
    expect(pass).to be_a(EO::Loot::Pass)
  end

  it 'finds what the character carries' do
    expect([context.charm, context.gauntlet, context.weapon_inv, context.disk]).to eq([charm, gauntlet, [:knife], :my_disk])
    expect(context.disk_full).to eq('Nisugi' => false, 'Ann' => false)
  end

  # The pass is built once and run room after room. A disk not yet in the
  # room when it was built was never used for the whole hunt.
  it 'looks for the disks again as each pass starts' do
    pass
    allow(EO::Items::Disk).to receive(:mine).and_return(:late_disk)
    stub_const('Group', Module.new { define_singleton_method(:disks) { [Struct.new(:name).new('Nisugi')] } })
    stub_const('Spell', Class.new { define_singleton_method(:[]) { |_name| Struct.new(:active?).new(true) } })
    allow(pass).to receive(:say)
    pass.start
    expect([context.disk, context.disk_full]).to eq([:late_disk, { 'Nisugi' => false }])
  end

  it 'gives the floor and the pass libeo\'s own hands, which never pause' do
    expect(pass.instance_variable_get(:@hands)).to be_a(EO::Loot::Handler)
    expect(pass.instance_variable_get(:@floor)).to be_a(EO::Loot::Floor)
  end

  it 'skins only when skinning is on' do
    expect(pass.instance_variable_get(:@skin).call).to be_a(EO::Skinning::Pass)
    settings[:skin_enable] = false
    expect(described_class.build(settings, say: ->(**) {}).instance_variable_get(:@skin)).to be_nil
  end

  it 'learns an unlootable item into the settings through the stow' do
    settings[:log_unlootables] = true
    context.learn(:unlootable, Struct.new(:name, :type).new('odd thing', nil))
    expect(settings[:unlootable]).to eq(['odd thing'])
  end
end

RSpec.describe EO::Loot::Hooks, '.lists' do
  let(:obj) { Struct.new(:id, :name, :noun) }
  let(:backpack) { obj.new('1', 'patchwork dwarf skin backpack') }
  let(:cloak) { obj.new('2', 'nacreous plumille cloak') }
  let(:sack) { obj.new('3', 'grey sack') }
  let(:bandolier) { obj.new('4', 'iron boar hide bandolier') }
  let(:knife) { obj.new('5', 'narrow vultite knife') }
  let(:inv) { [backpack, cloak, sack, bandolier] }
  let(:settings) do
    { overflow_containers: 'grey sack', appraisal_container: 'cloak', skin_enable: true, skin_sheath: 'bandolier', skin_weapon: 'vultite knife' }
  end
  let(:sent) { [] }
  let(:command) { ->(cmd, _re, **) { sent << cmd; [] } }
  let(:context) { Struct.new(:settings, :weapon_inv).new(settings, [knife]) }
  let(:lists) do
    Class.new do
      attr_accessor :list, :checked, :checks

      def initialize(list) = (@list = list; @checked = false; @checks = 0)
      def checked? = @checked
      def check(**) = (@checks += 1; @checked = true)
    end
  end
  let(:stow) { lists.new({ box: backpack, default: cloak }) }
  let(:ready) { lists.new({}) }

  before do
    items = inv
    stub_const('GameObj', Class.new { define_singleton_method(:inv) { items } })
    [['StowList', stow, :stow_list], ['ReadyList', ready, :ready_list]].each do |name, fake, reader|
      stub_const(name, Module.new do
        define_singleton_method(reader) { fake.list }
        define_singleton_method(:checked?) { fake.checked? }
        define_singleton_method(:check) { |**kw| fake.check(**kw) }
        define_singleton_method(:valid?) { |**| fake.list.values.compact.all? { |v| items.include?(v) } }
      end)
    end
  end

  it 'reads the lists Lich does not have, and finds the bags and the skinning gear' do
    EO::Loot::Hooks.lists(context, command)
    expect([stow.checks, ready.checks]).to eq([1, 1])
    expect(sent).to eq(['flag righthand off', 'flag lefthand off'])
    expect(stow.list).to include(overflow_container: sack, appraisal_container: cloak)
    expect(ready.list).to include(skin_sheath: bandolier, skin_weapon: knife)
  end

  it 'leaves the lists Lich has and that still name what is worn' do
    stow.checked = true
    ready.checked = true
    EO::Loot::Hooks.lists(context, command)
    expect([stow.checks, ready.checks]).to eq([0, 0])
  end

  it 'is what libeo runs as it loads, with the weapons read first' do
    allow(EO::Loot::Hooks).to receive(:weapons).and_return([knife])
    allow(EO::Loot::Hooks).to receive(:command).and_return(command)
    ReadyList.const_set(:ORIGINAL_READY_LIST, [])
    EO::Loot::Hooks.setup(settings)
    expect(ready.list).to include(skin_weapon: knife)
  end
end
