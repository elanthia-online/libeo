# frozen_string_literal: true

# Standing up and kneeling down, a few tries at most. A web, a bind or a
# creature's hold keeps a character where it is, and a script that tries
# until it works never gets past one.
module EO
  # STAND until standing.
  #
  # @param tries [Integer]
  # @return [Boolean] whether the character is standing
  def self.stand(tries: 5)
    tries.times do
      return true if standing?

      fput 'stand'
      settle
    end
    standing?
  end

  # KNEEL until kneeling.
  #
  # @param tries [Integer]
  # @return [Boolean] whether the character is kneeling
  def self.kneel(tries: 5)
    tries.times do
      return true if kneeling?

      fput 'kneel'
      settle
    end
    kneeling?
  end
end
