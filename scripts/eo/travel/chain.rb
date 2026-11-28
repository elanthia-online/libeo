# frozen_string_literal: true

module EO
  # Chaining bounties: a task turned in every ten minutes with a full head.
  # The bounty's experience fills the head to 2000 and the rest is split,
  # half absorbed at once; a task cannot be turned in while the head holds
  # more than its cap. So: planar and order rubbed right before the
  # turn-in, when their effect is not already up; one reducer right after
  # it, to get back under the cap before the next hunt fills the head
  # again; elemental's chaos roll spent when a gem or heirloom task starts.
  module Chain
    module_function

    # The reducers that can be listed, in no particular order.
    REDUCERS = %i[longterm spirit].freeze
    LONGTERM_NONE = /You do not have any Long-Term Experience Boosts to redeem\./
    LONGTERM_DONE = /You have deducted 500 experience points from your field experience/
    # Field experience a minute a head absorbs at least, out of the hunt.
    MIN_ABSORB = 30.0

    # @return [Integer] field experience over the cap, 0 when under it
    def excess = [Experience.fxp_current.to_i - Experience.fxp_max.to_i, 0].max

    # @return [Boolean] whether the head holds more than the cap
    def over_cap? = excess.positive?

    # Right before a turn-in: planar (the cap) and order (bounty points),
    # each only when its effect is not up, from chaos when the orb is spent.
    #
    # @param planar [Boolean]
    # @param order [Boolean]
    # @return [Hash{Symbol => Symbol}] what each rub came to
    def before_turn_in(planar: false, order: false)
      done = {}
      done[:planar] = Brooch.use(:planar) if planar && !Brooch.up?(:planar)
      done[:order] = Brooch.use(:order) if order && !Brooch.up?(:order)
      done
    end

    # Field experience absorbed a minute, estimated as ebounty's
    # check_exp does: per two-minute pulse, 25 + Logic bonus / 5 + 2 in a
    # node + field experience / 200 (at most 10) + 1 when grouped; never
    # under 30 a minute, what a head out of the hunt absorbs at least.
    #
    # @return [Float]
    def absorb_per_minute
      node = Room.current&.tags.to_a.any? { |t| t =~ /\A(?:super)?node\z/ } ? 2 : 0
      grouped = Lich::Gemstone::Group.members.to_a.empty? ? 0 : 1
      per_pulse = 25 + (Stats.enhanced_log[1].to_i / 5) + node + [Experience.fxp_current.to_i / 200, 10].min + grouped
      [per_pulse / 2.0, MIN_ABSORB].max
    rescue StandardError
      MIN_ABSORB
    end

    # @param amount [Integer] field experience
    # @return [Float] minutes to absorb it at the current rate
    def minutes_to_absorb(amount) = amount.to_f / absorb_per_minute

    # What the reducer decision saw, for the log.
    #
    # @param window [Numeric, nil] minutes the overflow has to absorb in
    # @return [Hash]
    def reading(window: nil)
      { fxp: Experience.fxp_current.to_i, cap: Experience.fxp_max.to_i, over: excess,
        per_minute: absorb_per_minute.round(1), absorb_minutes: minutes_to_absorb(excess).round(1),
        window: window&.round(1) }
    end

    # Right after a turn-in: one reducer, the first in the list that works,
    # when the head is over its cap and the overflow will not absorb by
    # itself within +window+ minutes (the time until the next turn-in can
    # be, say the Next Bounty cooldown).
    #
    # @param reducers [Array<Symbol, String>] :longterm, :spirit, in order
    # @param window [Numeric, nil] minutes to absorb in; nil always reduces when over
    # @return [Symbol, nil] the reducer used, :absorbs when the overflow
    #   will absorb in time, nil when none was needed or none worked
    def reduce(reducers, window: nil)
      @brooch_said = nil
      return nil unless over_cap?
      return :absorbs if window && minutes_to_absorb(excess) <= window

      Array(reducers).map(&:to_sym).each do |reducer|
        case reducer
        when :longterm
          return :longterm if EO.result('boost longterm', Regexp.union(LONGTERM_NONE, LONGTERM_DONE)).to_s =~ LONGTERM_DONE
        when :spirit
          @brooch_said = Brooch.use(:spirit)
          return :spirit if %i[spirit chaos].include?(@brooch_said)
        end
      end
      nil
    end

    # @return [Symbol, nil] what Brooch.use answered for the last spirit
    #   reducer tried (:none, :no_brooch, :spent, an orb), for the log
    def brooch_said = @brooch_said

    # When a gem or heirloom task starts: chaos rubbed if it will give
    # elemental and Lumnis' Fortitude is not already up, so the roll is
    # spent where its rerolls count.
    #
    # @return [Symbol, nil] as Brooch.use_chaos_if, nil when not needed
    def elemental
      return nil if Brooch.up?(:element)

      Brooch.use_chaos_if(:element)
    end
  end
end
