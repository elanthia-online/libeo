# frozen_string_literal: true

# Kneeling down, a few tries at most. A web, a bind or a creature's hold
# keeps a character where it is, and a script that tries until it works
# never gets past one. Standing up the same way is EO.stand (command.rb).
module EO
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
