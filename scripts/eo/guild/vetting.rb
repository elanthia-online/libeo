# frozen_string_literal: true

module EO
  module Guild
    # Whether a task is one the character takes.
    module Vetting
      module_function

      # Every kind of task a character can choose not to take.
      KINDS = %w[boss_culling culling heirloom_loot skinning heirloom_search foraging rescue escort kill_bandits gem_collecting].freeze

      # The kinds a character does not take.
      #
      # @param wanted [Array<String>] the kinds they do
      # @return [Array<String>]
      def unwanted_kinds(wanted)
        KINDS - wanted
      end

      # Whether to hand a task back: its creature, herb, gem or place is on
      # an exclusion list, or it is of a kind not taken. The exclusion lists
      # are lower-cased where they stand.
      #
      # @param type [Symbol] Bounty.type
      # @param task [Object] Bounty.task
      # @param exclude [Hash{Symbol => Array<String>}] the lists, under
      #   :creature, :herb, :gem and :location
      # @param wanted [Array<String>] the kinds of task taken
      # @return [Array(Boolean, String)] whether to hand it back, and for an
      #   exclusion what to say of it
      def reject?(type, task, exclude:, wanted:)
        req = task.requirements
        listed = ->(key, value) { exclude[key].length.positive? && value&.downcase =~ Regexp.union(exclude[key].map!(&:downcase)) }

        if listed.call(:creature, req[:creature])
          [true, "#{task.creature.capitalize} is in the excluded list. Turning in bounty!"]
        elsif listed.call(:herb, req[:herb])
          [true, "#{task.herb.capitalize} is in the excluded list. Turning in bounty!"]
        elsif listed.call(:gem, req[:gem])
          [true, "#{task.gem.capitalize} is in the excluded list. Turning in bounty!"]
        elsif listed.call(:location, req[:area])
          [true, "#{task.area} is in the excluded list. Turning in bounty!"]
        elsif Tables::TASK_TYPES[type] == 'kill_creatures' && wanted.grep(/culling/).none?
          [true, nil]
        elsif type == :heirloom && task.action == 'search' && !wanted.include?('heirloom_search')
          [true, nil]
        elsif type == :heirloom && task.action == 'loot' && !wanted.include?('heirloom_loot')
          [true, nil]
        elsif unwanted_kinds(wanted).grep(Tables::TASK_TYPES[type]).any?
          [true, nil]
        else
          [false, nil]
        end
      end
    end
  end
end
