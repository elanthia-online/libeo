# frozen_string_literal: true

# What a script lends the library. Every e-script has its own way to send a
# command and read the answer, to wait out roundtime, to walk somewhere and
# to print a message, and they are not the same: one retries where another
# gives up, one waits longer, one checks something first. Code that moved
# here from a script must go on doing those things that script's way, so the
# script hands its helpers over when it starts and the library calls
# whichever belong to the script that is running:
#
#   EO.use(command: MyScript.method(:get_command),
#          result:  MyScript.method(:get_res),
#          wait:    MyScript.method(:wait_rt),
#          go:      MyScript.method(:go2),
#          say:     MyScript.method(:msg))
#
# Arguments pass through untouched, so a module is written against the
# helpers of the script it serves. A script may lend helpers under any other
# name too, for a module that needs more of it (EO.helper).
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

  # Send a command and collect the lines of its answer, the running script's way.
  #
  # @return [Object] what the script's helper returns
  # @raise [NoHelper]
  def self.command(...) = helper(:command).call(...)

  # Send a command and return the line that answers it, the running script's way.
  #
  # @return [Object] what the script's helper returns
  # @raise [NoHelper]
  def self.result(...) = helper(:result).call(...)

  # Wait out roundtime, the running script's way.
  #
  # @return [Object] what the script's helper returns
  # @raise [NoHelper]
  def self.settle(...) = helper(:wait).call(...)

  # Walk somewhere, the running script's way.
  #
  # @return [Object] what the script's helper returns
  # @raise [NoHelper]
  def self.go2(...) = helper(:go).call(...)

  # Print a message, the running script's way.
  #
  # @return [Object] what the script's helper returns
  # @raise [NoHelper]
  def self.say(...) = helper(:say).call(...)
end
