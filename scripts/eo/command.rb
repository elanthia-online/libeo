# frozen_string_literal: true

module EO
  # "...wait N seconds." in a command's answer: the character was still in
  # roundtime, the command did not run, and it is sent again once the wait is
  # over. A "Roundtime: N sec." line is what a command that did run leaves
  # after it, and is part of its answer.
  WAIT = /^\.\.\.wait \d+ seconds\.$/

  # Send a command and collect its answer, re-sending after a roundtime
  # refusal.
  #
  # @param command [String]
  # @param regex [Regexp] what ends the answer
  # @param silent [Boolean, nil] hide the answer from the client
  # @param quiet [Boolean] hide the command from the client
  # @param timeout [Numeric, nil] seconds to wait for the answer, nil for Lich's default
  # @return [Array<String>] the answer's lines
  def self.command(command, regex, silent: nil, quiet: false, timeout: nil)
    stop = Regexp.union(regex, WAIT)
    opts = { silent: silent, quiet: quiet }
    opts[:timeout] = timeout if timeout
    loop do
      lines = Lich::Util.issue_command(command, stop, **opts)
      return lines unless lines.any? { |line| line.match?(WAIT) }
      # settle, not a bare waitrt?: its sleeps are where a script's guarded
      # sleep comes in (eloot's room cleanup checks its lease there)
      settle
    end
  end

  # Send a command and return the one line that answers it, re-sending after
  # a roundtime refusal.
  #
  # @param command [String]
  # @param regex [Regexp] what answers the command
  # @param timeout [Numeric] seconds to wait for the answer
  # @return [String, nil] the matching line, nil when nothing matched in time
  def self.result(command, regex, timeout: 3)
    stop = Regexp.union(regex, WAIT)
    loop do
      line = dothistimeout(command, timeout, stop)
      return line unless line.to_s.match?(WAIT)
      settle
    end
  end

  # Wait out cast and hard roundtime with a short settle either side, the way
  # every e-script does between commands.
  #
  # @return [void]
  def self.settle
    sleep 0.2
    waitcastrt?
    waitrt?
    sleep 0.2
  end

  # STAND until standing, a few tries at most: a web, a bind or a hold
  # keeps a character down, and the e-scripts used to try forever.
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

  # KNEEL until kneeling, a few tries at most, for the same reason.
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
