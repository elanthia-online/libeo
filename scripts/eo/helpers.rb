# frozen_string_literal: true

# Sending a command and reading its answer, waiting out roundtime, walking
# somewhere and printing a message: EO.command, EO.result, EO.lines,
# EO.settle, EO.go2 and EO.say. The library has its own way to do each
# (EO::Own), and that is what runs unless the running script has lent its
# own in its place:
#
#   EO.use(command: MyScript.method(:get_command),
#          go:      MyScript.method(:go2))
#
# Every e-script once had all of these, and they were not the same: one
# tried again where another gave up, one waited longer, one checked
# something first. A script whose way still matters lends it; arguments
# pass through to a lent helper untouched. A script may lend helpers under
# any other name too, for a module that needs more of it (EO.helper).
#
# A script that wants the library's debug messages lends debug, answering
# whether they are wanted now:
#
#   EO.use(debug: -> { MyScript.settings[:debug] })
module EO
  # Raised when library code needs a helper the running script did not lend.
  class NoHelper < StandardError; end

  @helpers ||= {}

  # Lend helpers to the library for a script. Called by the script when it
  # starts, before it uses any module; a later call adds to or replaces what
  # was lent before.
  #
  # @param script [String] the script's name; the running script by default
  # @param helpers [Hash{Symbol => #call}] each helper by its name
  # @return [void]
  # @raise [ArgumentError] when something lent cannot be called
  def self.use(script: Script.current.name, **helpers)
    uncallable = helpers.reject { |_name, helper| helper.respond_to?(:call) }.keys
    raise ArgumentError, "not callable: #{uncallable.join(', ')}" unless uncallable.empty?

    (@helpers[script.to_s] ||= {}).merge!(helpers)
    nil
  end

  # Take back everything a script lent.
  #
  # @param script [String]
  # @return [void]
  def self.forget(script: Script.current.name)
    @helpers.delete(script.to_s)
    nil
  end

  # @param name [Symbol]
  # @param script [String]
  # @return [Boolean] whether the script lent a helper by that name
  def self.helper?(name, script: Script.current&.name)
    @helpers.fetch(script.to_s, {}).key?(name)
  end

  # The helper the running script lent under a name.
  #
  # @param name [Symbol]
  # @param script [String]
  # @return [#call]
  # @raise [NoHelper] when the script lent none by that name, or no script is running
  def self.helper(name, script: Script.current&.name)
    @helpers.fetch(script.to_s, {}).fetch(name) do
      raise NoHelper, "#{script || 'no script'} lent libeo no :#{name} helper (EO.use)"
    end
  end

  # The running script's helper under a name, else the library's own.
  #
  # @api private
  def self.lent_or_own(name, own)
    helper?(name) ? helper(name) : Own.method(own)
  end

  # Send a command and collect the lines of its answer (Own.command),
  # unless the running script lent its way.
  #
  # @return [Array<String>]
  def self.command(...) = lent_or_own(:command, :command).call(...)

  # Send a command and return the line that answers it (Own.result), unless
  # the running script lent its way.
  #
  # @return [String, nil]
  def self.result(...) = lent_or_own(:result, :result).call(...)

  # Send a command unseen and collect the lines of its answer (Own.lines),
  # unless the running script lent its way.
  #
  # @return [Array<String>]
  def self.lines(...) = lent_or_own(:lines, :lines).call(...)

  # Wait out roundtime (Own.settle), unless the running script lent its way.
  #
  # @return [void]
  def self.settle(...) = lent_or_own(:wait, :settle).call(...)

  # Walk somewhere (Own.go2), unless the running script lent its way.
  #
  # @return [void]
  def self.go2(...) = lent_or_own(:go, :go2).call(...)

  # Print a message (Own.say), unless the running script lent its way.
  #
  # @return [void]
  def self.say(...) = lent_or_own(:say, :say).call(...)

  # @return [Boolean] whether the running script wants debug messages now
  def self.debug?
    helper?(:debug) && helper(:debug).call ? true : false
  end

  # The library's own helpers: what EO.command and the rest do for a script
  # that has not lent its own.
  module Own
    module_function

    # Roundtime in a command's answer: the command did not run, and is sent
    # again when the wait is over.
    ROUNDTIME = /(?:Roundtime:|\.\.\.wait) (\d+) [Ss]ec(?:onds)?\./i
    # The same for a command answered by one line, where the game may also
    # say "Wait N sec." or that a rash needs scratching first.
    BUSY = /(?:Roundtime:|\.\.\.wait|Wait) (\d+) [Ss]ec(?:onds?)?\.?|An uncontrollable urge to scratch the rash/

    # Send a command and collect its answer, sending it again after
    # roundtime.
    #
    # @param text [String] the command
    # @param pattern [Regexp] the line the answer starts at
    # @param silent [Boolean, nil] keep the answer from the client
    # @param quiet [Boolean] keep the command from the client
    # @param timeout [Numeric] seconds to wait for the answer
    # @return [Array<String>] the answer's lines
    def command(text, pattern, silent: nil, quiet: false, timeout: 5)
      pattern = Regexp.union(pattern, ROUNDTIME)
      loop do
        lines = Lich::Util.issue_command(text, pattern, usexml: true, silent: silent, quiet: quiet, timeout: timeout)
        say('debug', "command: #{text} | lines - #{lines}")
        return lines unless lines.any? { |line| line =~ ROUNDTIME }

        EO.settle
      end
    end

    # The same with neither the command nor its answer shown.
    #
    # @param text [String] the command
    # @param pattern [Regexp] the line the answer starts at
    # @return [Array<String>] the answer's lines
    def lines(text, pattern)
      command(text, pattern, silent: true, quiet: true)
    end

    # Send a command and return the line that answers it, sending it again
    # after roundtime.
    #
    # @param text [String] the command
    # @param pattern [Regexp, nil] the answer; any line when nil
    # @param timeout [Numeric] seconds to wait for it
    # @return [String, nil] nil when nothing answered in time
    def result(text, pattern = nil, timeout: 3)
      say('debug', "command: #{text}")
      pattern = pattern.nil? ? Regexp.union(/.*?/, BUSY) : Regexp.union(pattern, BUSY)
      loop do
        line = dothistimeout(text, timeout, pattern)
        return line unless line =~ BUSY

        EO.settle
      end
    end

    # Wait out cast roundtime and roundtime, with a moment either side.
    #
    # @return [void]
    def settle
      sleep 0.2
      waitcastrt?
      waitrt?
      sleep 0.2
    end

    # Walk to a room or a tagged place with go2, coming out of hiding
    # first. Nothing is done when already there.
    #
    # @param place [Integer, String] a room id or a tag
    # @return [void]
    def go2(place)
      say('debug', "place: #{place}")
      fput('unhide') if hidden? || invisible?

      return if Room.current.id.to_s == place.to_s || Room.current.tags.include?(place)

      say('error', 'unknown room location') if Room.current.id.nil?
      Script.run('go2', "#{place} --disable-confirm", { quiet: true })
    end

    # Print a message in one of Lich's colours. A debug message shows as
    # speech, and only when the running script wants them (EO.debug?).
    # Both ways the e-scripts called theirs are taken: say('info', 'text')
    # and say(type: 'info', text: 'text').
    #
    # @param type [String] yellow, orange, teal, green, plain, info, error, debug, ...
    # @param text [Object] a Hash or Array is shown inspected
    # @param space [Boolean] an empty line before and after
    # @return [void]
    def say(*args, type: 'info', text: '', space: false)
      type, text = args if args.size == 2
      return if type == 'debug' && !EO.debug?

      text = case text
             when Hash then text.inspect.gsub('#<', '#')
             when String then text.gsub('#<', '#')
             else text.to_s
             end
      respond '' if space
      Lich::Messaging.msg(type == 'debug' ? 'speech' : type, text)
      respond '' if space
    end
  end
end
