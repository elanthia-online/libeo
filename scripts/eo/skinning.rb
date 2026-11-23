# frozen_string_literal: true

module EO
  # Skinning: which of the dead to skin and with what kind of tool, getting
  # ready, the SKIN itself, and standing up after.
  #
  # Commands go through the running script's helpers (EO.use). The helper
  # this needs: command(text, pattern, silent:, quiet:) answering the lines.
  module Skinning
    module_function

    # Creatures a blade does nothing to: they take a blunt tool.
    BLUNT = /krynch|stone mastiff|krag dweller|cavern urchin|massive boulder/i

    # Creatures never skinned, by name.
    NEVER = /(?:ethereal|ghostly|unwordly|Grimswarm|child)/

    SKIN_ANSWER = Regexp.union(
      /You skinned/i,
      /You botched/i,
      /already been/i,
      /cannot skin/i,
      /must be a member/i,
      /can only skin/i,
      /You are unable to break through/i,
      /You break through the crust of the/i,
      /You crack open a portion/i,
      /Because your account is free/i,
      /it's not possible to get a worthwhile/i
    )

    # A skinning that broke something open and left a gem in the left hand.
    BROKE_OPEN = Regexp.union(
      /You break through the crust of the .+ and withdraw (.+)!/i,
      /You crack open a portion of the .+ and uncover (.+)!/i
    )

    # A creature that cannot be skinned, now or ever. The second is a
    # creature such as an OSA ship captain, ruined with alchemical components.
    CANNOT = /You cannot skin|ruined with alchemical components/

    # A rotting chimera is skinned only now and then: when DESCRIBE shows
    # its scorpion tail.
    #
    # @param obj [GameObj]
    # @return [Boolean]
    def sometimes?(obj)
      if obj.name =~ /rotting chimera/
        lines = EO.command('describe chimera', /The twisted and confused form/, silent: true, quiet: true)
        return true if lines.any? { |line| line =~ /A huge scorpion tail rises high from the rear/ }
      end

      false
    end

    # Whether a dead creature is left unskinned.
    #
    # @param obj [GameObj]
    # @param unskinnable [Array<String>] names learned not to skin
    # @param exclude [Array<String, Regexp>] names the character leaves alone
    # @param never [Regexp] names never searched or skinned
    # @return [Boolean]
    def skip?(obj, unskinnable:, exclude:, never:)
      ((unskinnable.include?(obj.name) && !sometimes?(obj)) ||
        obj.type =~ /bandit/ ||
        obj.name =~ NEVER ||
        (exclude.length.positive? && obj.name =~ Regexp.union(exclude)) ||
        obj.name.match?(never)) ? true : false
    end

    # The dead that match a bounty's creature.
    #
    # @param objs [Array<GameObj>]
    # @param creature [String] the creature the bounty names
    # @return [Array<GameObj>]
    def for_bounty(objs, creature)
      wanted = creature.to_s.downcase
      objs.select { |obj| obj.name.to_s.downcase.include?(wanted) }
    end

    # Split the dead into those a blade skins and those that take a blunt tool.
    #
    # @param objs [Array<GameObj>]
    # @return [Array(Array<GameObj>, Array<GameObj>)] the edged, then the blunt
    def by_tool(objs)
      blunt = objs.find_all { |obj| obj.name =~ BLUNT }
      [objs.reject { |obj| obj.name =~ BLUNT }, blunt]
    end

    # Get ready to skin: kneel while nothing is there to fight, Sigil of
    # Resolve, and Nature's Touch (604) kept up past the skinning, three casts at most.
    #
    # @param kneel [Boolean]
    # @param resolve [Boolean]
    # @param nature [Boolean] keep 604 up
    # @return [void]
    def prepare(kneel:, resolve:, nature:)
      EO.kneel if GameObj.targets.empty? && kneel

      if resolve &&
         Spell['Sigil of Resolve'].affordable? &&
         !Spell['Sigil of Resolve'].active?
        Spell['Sigil of Resolve'].cast
      end

      return unless nature && Spell[604].affordable? && (!Spell[604].active? || (Spell[604].timeleft * 60).truncate <= 10)

      3.times do
        break if Spell[604].active? && (Spell[604].timeleft * 60).truncate > 5

        Spell[604].cast
        sleep(0.1)
      end
    end

    # SKIN one creature with the tool in the hand named. A gem a skinning
    # broke out is stowed from the left hand.
    #
    # @param obj [GameObj]
    # @param hand [String] 'right' or 'left', the hand holding the tool
    # @return [Symbol] :cannot (this creature is not one to skin) or :done
    def skin(obj, hand)
      res = dothistimeout("skin ##{obj.id} #{hand}", 2, SKIN_ANSWER)
      if res =~ CANNOT
        :cannot
      else
        fput "stow gem ##{GameObj.left_hand.id}" if res =~ BROKE_OPEN
        :done
      end
    end

    # Stand up after skinning, on the offensive while nothing is there to
    # fight, and go back to the stance held before.
    #
    # @param stance [Proc] given a stance's name, changes to it
    # @return [void]
    def stand_up(stance:)
      return if standing?

      prev_stance = Stance.current
      stance.call('offensive') if GameObj.targets.empty?
      EO.stand
      stance.call(prev_stance)
    end
  end
end
