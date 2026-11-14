# frozen_string_literal: true

require 'date'

module EO
  # The game's day: the date in US Eastern time, where daily counts reset
  # at midnight. Worked out from the daylight-saving rule (second Sunday of
  # March to first Sunday of November), as Ruby on Windows has no zone data.
  #
  # @param now [Time]
  # @return [String] "2026-11-13"
  def self.eastern_day(now = Time.now)
    utc = now.getutc
    (utc - ((eastern_daylight?(utc) ? 4 : 5) * 3600)).strftime('%Y-%m-%d')
  end

  # @param utc [Time] a moment, in UTC
  # @return [Boolean] whether US Eastern time is on daylight saving then
  def self.eastern_daylight?(utc)
    sunday = ->(month, nth) { 1 + ((7 - Time.utc(utc.year, month, 1).wday) % 7) + (7 * (nth - 1)) }
    # 2:00 standard is 07:00 UTC; 2:00 daylight is 06:00 UTC
    utc >= Time.utc(utc.year, 3, sunday.call(3, 2), 7) && utc < Time.utc(utc.year, 11, sunday.call(11, 1), 6)
  end

  # A time the game printed in US Eastern ("Tue Feb 10 20:30:45 2026", the
  # zone word already taken off), as the moment it is whatever zone this
  # machine is in. The hour the clocks go back is read as daylight time.
  #
  # @param text [String]
  # @return [Time]
  def self.parse_eastern(text)
    parts = Date._parse(text)
    wall = Time.utc(parts[:year], parts[:mon], parts[:mday], parts[:hour] || 0, parts[:min] || 0, parts[:sec] || 0)
    daylight = wall + (4 * 3600)
    eastern_daylight?(daylight) ? daylight : wall + (5 * 3600)
  end

  # The quintuple orb brooch, a Rings of Lumnis prize: five orbs, each with
  # a few rubs a day. Planar raises the field experience cap for thirty
  # minutes (Lumnis' Enlightenment), Spiritual absorbs experience at once,
  # Elemental gives rerolls on guild tasks for thirty minutes (Lumnis'
  # Fortitude), Order adds bounty points at turn-in, and Chaos gives one of
  # the other four, the one ANALYZE names, chosen again after each rub.
  #
  # The brooch must be worn or held to be used; one kept in a container is
  # taken out for the rub and put back.
  #
  # The rubs used are tallied here for the game's day, so ANALYZE is asked
  # only when the tally cannot say: the first use of a day or a session,
  # once when the tally has an orb spent, and when chaos is wanted after a
  # chaos rub changed what it gives (only a chaos rub changes it). A rub
  # made by hand leaves the tally short, which the brooch's refusal then
  # corrects; a refused rub costs nothing. The orb the brooch is on is never
  # taken from memory: every rub is whispered for first.
  module Brooch
    module_function

    # Each orb by the name ANALYZE gives it, the word WHISPER takes, and its
    # colour, which is how WHISPER names the orb the brooch is already on.
    ORBS = {
      planar: { name: 'Planar', whisper: 'planar', color: 'red' },
      spirit: { name: 'Spiritual', whisper: 'spirit', color: 'blue' },
      element: { name: 'Elemental', whisper: 'element', color: 'green' },
      chaos: { name: 'Chaos', whisper: 'chaos', color: 'black' },
      order: { name: 'Order', whisper: 'order', color: 'white' },
    }.freeze

    # The Buffs entry an orb leaves, for the orbs that last.
    BUFFS = { planar: "Lumnis' Enlightenment", element: "Lumnis' Fortitude", order: "Lumnis' Repose" }.freeze

    NOUN = /\bbrooch\b/
    NAME = /orb brooch/
    ANALYZE_START = /^You analyze the .*brooch and sense that the creator has provided the following information:$/
    # ANALYZE's last line: the brooch is bound to an account or a character.
    ANALYZE_END = /^The brooch is restricted to this \w+\.$/
    # "it is unresponsive" is the answer to a word WHISPER does not take.
    WHISPER_DONE = /is now attuned to the (\w+) ring|already centered on the (\w+) orb|it is unresponsive/
    # The brooch is on an orb: moved to that ring, or already on that colour.
    WHISPER_ON = /is now attuned to the (\w+) ring|already centered on the (\w+) orb/
    # A rub's answer: the energy that took hold (a chaos rub names the orb
    # it gave), or the brooch has no use left for this orb.
    RUB = /energy flows into you|ebbs weakly, but nothing further happens/
    SPENT = /ebbs weakly, but nothing further happens/
    # A chaos rub names the orb it gave after its own chaotic energy.
    REPLACED = /as (\w+) energy soon replaces it/
    FLOWS = /(\w+) energy flows into you/
    ENERGY = { 'planar' => :planar, 'spiritual' => :spirit, 'elemental' => :element, 'order' => :order, 'orderly' => :order, 'ordered' => :order,
               'chaotic' => :chaos }.freeze

    # What ANALYZE says: the orb the brooch is on, the orb chaos will give,
    # and each orb's rubs used and allowed today.
    Status = Struct.new(:current, :chaos_gives, :uses, keyword_init: true) do
      # @param orb [Symbol]
      # @return [Integer] rubs left today
      def left(orb)
        used, max = uses.fetch(orb, [0, 0])
        [max - used, 0].max
      end
    end

    # ANALYZE's lines as a Status.
    #
    # @param lines [Array<String>]
    # @return [Status]
    def parse(lines)
      text = lines.join("\n")
      by_name = ORBS.to_h { |key, orb| [orb[:name], key] }
      current = by_name[text[/It is currently set to (\w+)/, 1]]
      gives = by_name[text[/will use the (\w+) benefit/, 1]]
      uses = {}
      used_at = text.index('You have used each orb')
      text[used_at..].to_s.scan(/^\s*(\w+): (\d+) out of (\d+)/) { |name, used, max| uses[by_name[name]] = [used.to_i, max.to_i] if by_name[name] }
      Status.new(current: current, chaos_gives: gives, uses: uses)
    end

    # ANALYZE MY BROOCH's lines, from its first to the line that says what the
    # brooch is restricted to. Lich strips the prompt from the text this reads,
    # so no prompt ends the wait: without an end pattern it ran the full five
    # seconds. Ending sooner would leave the lines after it in the stream.
    #
    # @api private
    # @return [Array<String>]
    def analyze
      Lich::Util.issue_command('analyze my brooch', ANALYZE_START, ANALYZE_END, usexml: false, silent: true, quiet: true)
    end

    # @return [GameObj, nil] the brooch worn, held or in a container
    def find
      held = [GameObj.right_hand, GameObj.left_hand].find { |obj| brooch?(obj) }
      return held if held

      GameObj.inv.to_a.find { |obj| brooch?(obj) } || containers.values.flatten.find { |obj| brooch?(obj) }
    end

    # @api private
    def brooch?(obj) = !obj.nil? && obj.noun.to_s =~ NOUN && obj.name.to_s =~ NAME

    # @api private
    def containers = GameObj.containers.to_h

    # Run the block with the brooch usable: taken out of its container into
    # an empty hand first, and put back after.
    #
    # @yield the brooch is worn or held
    # @return [Object, nil] the block's value, nil when there is no brooch
    def with_brooch
      brooch = find
      return nil if brooch.nil?

      from = containers.find { |_id, contents| Array(contents).any? { |obj| obj.id == brooch.id } }&.first
      return yield if from.nil?

      empty_hands
      EO.result("get ##{brooch.id}", /You (?:get|remove|grab|pick)|Get what\?/)
      begin
        yield
      ensure
        EO.result("put ##{brooch.id} in ##{from}", /You (?:put|place|slip|tuck|drop)|Put what\?|won't fit/)
        fill_hands
      end
    end

    # @return [Status, nil] ANALYZE MY BROOCH, nil when there is no brooch
    def status
      with_brooch { parse(analyze) }
    end

    # @param orb [Symbol] a key of BUFFS
    # @return [Boolean] whether that orb's effect is up
    def up?(orb)
      name = BUFFS[orb]
      !name.nil? && Effects::Buffs.active?(name)
    end

    # Rub one orb, or chaos when chaos will give it: the orb's own rub
    # first, while it has one left today.
    #
    # @param orb [Symbol] :planar, :spirit, :element or :order
    # @param chaos [Boolean] use chaos when the orb is spent and chaos gives it
    # @return [Symbol] the orb that took hold, :spent when the brooch refused,
    #   :none when neither the orb nor chaos could give it (or the brooch
    #   did not answer), :no_brooch
    def use(orb, chaos: true)
      result = with_brooch do
        pick = if rubs_left?(orb) then orb
               elsif chaos && chaos_gives?(orb) then :chaos
               end
        pick.nil? ? :none : spend(pick)
      end
      result || :no_brooch
    end

    # Rub chaos if it will give +orb+ now, to spend that roll where it helps.
    #
    # @param orb [Symbol]
    # @return [Symbol] as #use, :none when chaos gives something else
    def use_chaos_if(orb)
      result = with_brooch { chaos_gives?(orb) ? spend(:chaos) : :none }
      result || :no_brooch
    end

    # --- the day's tally -----------------------------------------------------

    # The tally for the game's day, nil when there is none yet or the day
    # has turned.
    #
    # @api private
    # @return [Hash, nil] day, uses (orb => [used, max]), chaos_gives (nil
    #   when not known), checked (orbs ANALYZE has confirmed spent)
    def tally(now: Time.now)
      @tally = nil if @tally && @tally[:day] != EO.eastern_day(now)
      @tally
    end

    # Forget the tally, so the next use asks ANALYZE.
    #
    # @return [void]
    def forget
      @tally = nil
    end

    # ANALYZE into the tally, the brooch whispered to chaos first: ANALYZE
    # names what chaos will give only while the brooch is on chaos ("set
    # to Chaos, which will use the Planar benefit"). A whisper costs
    # nothing, and every rub whispers for its own orb anyway. Without an
    # answer the tally stays as it was.
    #
    # @api private
    # @return [Hash, nil] the tally
    def sync
      attune(:chaos)
      state = parse(analyze)
      return tally if state.uses.empty?

      spent = state.uses.keys.reject { |orb| state.left(orb).positive? }
      @tally = { day: EO.eastern_day, uses: state.uses, chaos_gives: state.chaos_gives, checked: spent }
    end

    # @api private
    # @return [Integer] rubs the tally has left for an orb
    def left(orb)
      used, max = (tally || {}).fetch(:uses, {}).fetch(orb, [0, 0])
      [max - used, 0].max
    end

    # Whether an orb has a rub left today. The tally answers; when it has
    # the orb spent, ANALYZE is asked once to be sure, and not again that day.
    #
    # @api private
    def rubs_left?(orb)
      return false if (tally || sync).nil?
      return true if left(orb).positive?
      return false if tally[:checked].include?(orb)

      sync
      tally[:checked] |= [orb]
      left(orb).positive?
    end

    # Whether chaos has a rub left and will give +orb+. What chaos gives
    # changes only with a chaos rub, and ANALYZE is asked right after one.
    #
    # @api private
    def chaos_gives?(orb)
      return false unless rubs_left?(:chaos)

      sync if tally[:chaos_gives].nil?
      tally && tally[:chaos_gives] == orb
    end

    # Whisper for an orb and rub it, and count the rub. Nothing is rubbed
    # unless the brooch says it is on that orb.
    #
    # @api private
    # @param pick [Symbol] the orb to rub, :chaos included
    # @return [Symbol] as #rub, :none when the whisper was not answered
    def spend(pick)
      unless attune(pick)
        forget
        return :none
      end
      got = rub
      uses = tally && tally[:uses][pick]
      if got == :unknown || uses.nil?
        forget
      elsif got == :spent
        uses[0] = uses[1]
        tally[:checked] |= [pick]
      else
        uses[0] += 1
        # a chaos rub picks the next orb chaos gives: read it now
        sync if pick == :chaos
      end
      got
    end

    # WHISPER MY BROOCH to the orb, every time: the brooch may have been
    # moved by hand, and a rub on the wrong orb spends that orb's use.
    #
    # @api private
    # @return [Boolean] whether the brooch is on the orb now
    def attune(orb)
      word, color = ORBS.fetch(orb).values_at(:whisper, :color)
      line = EO.result("whisper my brooch #{word}", WHISPER_DONE).to_s
      return false unless line =~ WHISPER_ON

      ring, on = Regexp.last_match(1), Regexp.last_match(2)
      ring ? ring.casecmp?(word) : on.casecmp?(color)
    end

    # RUB MY BROOCH.
    #
    # @return [Symbol] the orb whose energy took hold, or :spent
    def rub
      line = EO.result('rub my brooch', RUB, timeout: 5).to_s
      return :spent if line =~ SPENT

      energy = line[REPLACED, 1] || line[FLOWS, 1]
      ENERGY.fetch(energy.to_s.downcase, :unknown)
    end
  end
end
