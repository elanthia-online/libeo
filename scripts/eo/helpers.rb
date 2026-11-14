# frozen_string_literal: true

# A script's own helpers in front of the library's.
#
# The library sends a command and reads its answer, waits out roundtime,
# walks and prints through EO.command, EO.result, EO.settle, EO.go2 and
# EO.say (command.rb, messages.rb, travel.rb). A script that has its own
# way of doing one of these, and has not yet been moved onto the library's,
# lends it, and its helper is used in place of the library's for as long as
# that script is the one running:
#
#   EO.use(command: MyScript.method(:get_command),
#          go:      MyScript.method(:go2))
#
# Arguments pass through to a lent helper untouched. A script may lend
# helpers under any other name too, for a module that needs more of it
# (EO.helper).
#
# This file is loaded after the files that define the library's own, and
# stands in front of them.
module EO
  # Raised when library code needs a helper the running script did not lend.
  class NoHelper < StandardError; end

  @helpers ||= {}

  # The library's own, as they stood when this file was loaded.
  @own = { command: method(:command), result: method(:result), wait: method(:settle), go: method(:go2), say: method(:say) }

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

  # @api private
  # @return [String, nil] the running script's name, nil outside Lich
  def self.running = defined?(Script) && Script.respond_to?(:current) ? Script.current&.name : nil

  # @param name [Symbol]
  # @param script [String]
  # @return [Boolean] whether the script lent a helper by that name
  def self.helper?(name, script: running)
    @helpers.fetch(script.to_s, {}).key?(name)
  end

  # The helper the running script lent under a name.
  #
  # @param name [Symbol]
  # @param script [String]
  # @return [#call]
  # @raise [NoHelper] when the script lent none by that name, or no script is running
  def self.helper(name, script: running)
    @helpers.fetch(script.to_s, {}).fetch(name) do
      raise NoHelper, "#{script || 'no script'} lent libeo no :#{name} helper (EO.use)"
    end
  end

  # The running script's helper under a name, else the library's own.
  #
  # @api private
  def self.lent_or_own(name) = helper?(name) ? helper(name) : @own.fetch(name)

  # Send a command and collect the lines of its answer.
  #
  # @return [Array<String>]
  def self.command(...) = lent_or_own(:command).call(...)

  # Send a command and return the line that answers it.
  #
  # @return [String, nil]
  def self.result(...) = lent_or_own(:result).call(...)

  # Wait out roundtime.
  #
  # @return [void]
  def self.settle(...) = lent_or_own(:wait).call(...)

  # Walk somewhere.
  #
  # @return [Object] what the walk answers
  def self.go2(...) = lent_or_own(:go).call(...)

  # Print a message.
  #
  # @return [void]
  def self.say(...) = lent_or_own(:say).call(...)

  # Send a command unseen and collect the lines of its answer: the running
  # script's lines helper, else the library's command with neither the
  # command nor its answer shown.
  #
  # @param text [String] the command
  # @param pattern [Regexp] the line the answer starts at
  # @return [Array<String>]
  def self.lines(text, pattern)
    return helper(:lines).call(text, pattern) if helper?(:lines)

    @own.fetch(:command).call(text, pattern, silent: true, quiet: true)
  end
end
