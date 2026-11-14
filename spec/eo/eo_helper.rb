# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/messages'
require_relative '../../scripts/eo/travel'
require_relative '../../scripts/eo/helpers'
require_relative '../../scripts/eo/posture'

# The libeo files are loaded by libeo.lic inside Lich. Specs load the one
# file under test and stand in for the Lich globals it touches with
# stub_const, so nothing here needs a running Lich.
module EOSpec
  # A room as the files see it: id, uid, tags, location, and exits (wayto)
  # keyed by neighbour id as a string.
  FakeRoom = Struct.new(:id, :uid, :tags, :location, :wayto, keyword_init: true) do
    def initialize(id:, uid: [], tags: [], location: nil, wayto: {})
      super(id: id, uid: uid, tags: tags, location: location, wayto: wayto)
    end

    def timeto = wayto.transform_values { 1 }
  end

  # A map of FakeRooms answering Room.list, Room[id], Room.current and the
  # two searches the files use.
  class FakeMap
    attr_accessor :current

    def initialize(rooms)
      @rooms = rooms.to_h { |r| [r.id, r] }
      @current = rooms.first
    end

    def list = @rooms.values

    def [](key)
      return @rooms[key] if key.is_a?(Integer)
      return @rooms[key.to_i] if key.to_s =~ /\A\d+\z/
      uid = key.to_s.sub(/\Au/i, '').to_i
      @rooms.values.find { |r| r.uid.include?(uid) }
    end

    # Unweighted breadth-first distances from +from+.
    def distances(from)
      dist = { from.id => 0 }
      queue = [from.id]
      until queue.empty?
        here = queue.shift
        @rooms[here].wayto.each_key do |n|
          n = n.to_i
          next if dist.key?(n)
          dist[n] = dist[here] + 1
          queue.push(n)
        end
      end
      dist
    end
  end
end

RSpec.shared_context 'a fake map' do
  let(:rooms) { [] }
  let(:map) { EOSpec::FakeMap.new(rooms) }

  before do
    fake = map
    room_class = Class.new do
      define_singleton_method(:list) { fake.list }
      define_singleton_method(:[]) { |key| fake[key] }
      define_singleton_method(:current) { fake.current }
    end
    fake.list.each do |room|
      room.define_singleton_method(:find_nearest) do |ids|
        dist = fake.distances(self)
        ids.select { |id| dist.key?(id) }.min_by { |id| dist[id] }
      end
      room.define_singleton_method(:dijkstra) { [nil, fake.distances(self)] }
    end
    stub_const('Room', room_class)
  end
end

# A running script that has lent the library its helpers. `sent` collects
# every command; `answers` maps a command (a String, or a Regexp it matches)
# to the lines the game gives back, each used once when given as an Array of
# Arrays. A command with no answer gets no lines.
RSpec.shared_context 'a script lending helpers' do
  let(:sent) { [] }
  let(:said) { [] }
  let(:went) { [] }
  let(:answers) { {} }

  def answer_to(command)
    key = answers.keys.find { |k| k.is_a?(Regexp) ? command =~ k : command == k }
    lines = answers[key]
    lines = lines.shift if lines.is_a?(Array) && lines.first.is_a?(Array)
    Array(lines)
  end

  before do
    stub_const('Script', Class.new { define_singleton_method(:current) { Struct.new(:name).new('spec') } })
    EO.use(
      command: ->(text, _pattern = nil, **) { sent << text && answer_to(text) },
      result: ->(text, _pattern = nil, **) { sent << text && answer_to(text).first },
      say: ->(type:, text:, **) { said << [type, text] },
      wait: -> { sent << :wait },
      go: ->(place) { went << place }
    )
  end

  after { EO.forget(script: 'spec') }
end

# Lich's Mana.pulse, noting in `pulses` each spell it was asked about.
RSpec.shared_context 'Lich mana' do
  let(:pulses) { [] }

  before do
    asked = pulses
    stub_const('Lich::Gemstone::Mana', Class.new { define_singleton_method(:pulse) { |spell = nil, **| asked << spell && false } })
  end
end

# The specs written against lent helpers, by file name. The two stand-ins
# below are theirs; a spec that came with the library's own helpers makes
# its own.
LENT_HELPER_SPECS = %w[cleanse_recovery cleanse guild_completion guild_dialogue guild_escort guild_forage guild_rescue guild herb_heal herb_sack herbs wander chain helpers posture].freeze

def lent_helper_spec?(example)
  LENT_HELPER_SPECS.include?(File.basename(example.metadata[:file_path], '_spec.rb'))
end

# Standing and kneeling are tried and answered true, except in a spec
# marked posture: true, which is about them.
RSpec.configure do |config|
  config.before do |example|
    allow(EO).to receive_messages(stand: true, kneel: true) if lent_helper_spec?(example) && !example.metadata[:posture]
  end
end

# Lich's Stash, as far as EO::Hands asks it: an item is in hand when a
# hand has its id, and the way to an item is open. A spec about the way
# stubs open_path_to itself.
RSpec.configure do |config|
  config.before do |example|
    next unless lent_helper_spec?(example)

    stub_const('Lich::Stash', Class.new do
      define_singleton_method(:in_hand?) { |item| [GameObj.right_hand&.id, GameObj.left_hand&.id].include?(item.id) }
      define_singleton_method(:open_path_to) { |_item| true }
    end)
  end
end
