# frozen_string_literal: true

module EO
  # Cleansing: getting rid of what is done to a character in a fight. This
  # file has what the rest stands on: the debuffs and room hazards by name,
  # the spell a character has for each job, TARGET and its answers, and the
  # list of hazards that would not be targeted.
  module Cleanse
    module_function

    # Debuffs a dispel removes.
    DEBUFFS = /Confusion|Vertigo|Sounds|Thought Lash|Mindwipe|Pious Trial|Powersink/
    # Magical things in a room that a dispel removes.
    MAGIC_GLOBES = /silvery blue globe|spiraling ghostly rift|chaotic spatial anomaly/i
    # The globes that are dispelled without being targeted first.
    UNTARGETED_GLOBES = /silvery blue globe|spiraling ghostly rift/
    RUNESTONES = /pale hovering runestone/i
    # Clouds a dispel does nothing to. Acidic mist is blown away instead.
    INVALID_CLOUDS = ['cloud of acidic mist', 'cloud of thick ethereal fog'].freeze
    ACIDIC_MIST = 'cloud of acidic mist'

    # Where a wound bears on casting or searching.
    INJURY_LOCATIONS = %w[leftHand rightHand leftArm rightArm leftEye rightEye nsys head].freeze

    # Every answer TARGET gives.
    TARGET_ANSWERS = Regexp.union(
      /^You can only target creatures, players, and creature-created hazards\.$/,
      /^Usage:  TARGET {player\|creature\|hazard}$/,
      /^You are now targeting .+\.$/,
      /^You are unable to discern the origin of .+\.$/,
      /^You discern that you are the origin of .+ and decide against targeting yourself\.$/,
      /^Suspecting that .+ is the origin of .+, you turn your attention towards \w+!$/
    )
    # The one answer that means a hazard is now targeted.
    TARGETED = /^Suspecting that .+ is the origin of .+, you turn your attention towards \w+!$/

    # The spells that do each job, the first a character knows being theirs.
    SPELLS = {
      disease: [113],
      dispel: [417, 1218, 119],
      poison: [114],
      webs: [209, 417, 1218, 119],
      breeze: [912, 612]
    }.freeze

    # @param job [Symbol] a key of SPELLS
    # @return [Spell, nil] the spell this character has for it
    def spell(job)
      SPELLS.fetch(job).map { |num| Spell[num] }.find(&:known?)
    end

    # TARGET a hazard.
    #
    # @param obj [GameObj]
    # @return [Boolean] whether the game turned the character's attention to it
    def target(obj)
      result = dothistimeout("target ##{obj.id}", 2, TARGET_ANSWERS)
      result.is_a?(String) && result =~ TARGETED ? true : false
    end

    # Ids of hazards that would not be targeted, so they are not tried
    # again: the latest two hundred.
    class BadTargets
      MAX_SIZE = 200

      # @param max_size [Integer]
      def initialize(max_size = MAX_SIZE)
        @max_size = max_size
        @list = []
      end

      # @param id [String]
      # @return [void]
      def <<(id)
        @list << id
        @list.shift while @list.size > @max_size
      end

      # @param id [String]
      # @return [Boolean]
      def include?(id)
        @list.include?(id)
      end
    end
  end
end
