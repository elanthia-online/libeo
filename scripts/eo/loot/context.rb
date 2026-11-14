# frozen_string_literal: true

module EO
  module Loot
    # What a looting pass reads and keeps: the settings, the stow, the
    # hands and containers it works with, the patterns that say what is
    # loot, and where to say something and to save what was learned. A
    # caller that keeps these itself (eloot's ELoot::Data) answers the same
    # names, so the pass takes either; this class is for one that does not.
    #
    # The settings and the stow are shared, not copied: a pass that learns
    # a crumbly item changes the caller's own list.
    class Context
      # What a pass keeps from one step to the next.
      STATE = %i[
        right_hand left_hand disk disk_full charm gauntlet blood_band coin_hand coin_container coin_bag
        coin_bag_full gambling_kit gambling_kit_full checked_bags sell_containers weapon_inv silent_open pool_command
      ].freeze

      # What a pass reads and does not change.
      READS = %i[
        loot_exclude_regex loot_keep_regex critter_exclude_regex allowed_special_types look_regex put_regex
      ].freeze

      attr_accessor(*STATE, *READS)

      # @return [Hash] eloot's settings
      attr_reader :settings

      # @return [EO::Stow]
      attr_reader :stow

      # @param settings [Hash] eloot's settings (EO::Settings.load_profile('eloot'))
      # @param say [Proc, nil] given type: and text:, shows a message; nothing
      #   is shown without one, and the type "debug" is for the caller's log
      # @param save [Proc, nil] writes the settings back after a pass learned
      #   something (a crumbly item, a bag that closes itself); nothing is
      #   saved without one
      # @param unlootable [Proc, nil] given an item the game said cannot be
      #   picked up
      # @param stow [EO::Stow, nil] the caller's own; one that learns through
      #   this context is made without one
      # @param state [Hash] any of STATE and READS
      # @raise [ArgumentError] a name that is neither
      def initialize(settings:, say: nil, save: nil, unlootable: nil, stow: nil, **state)
        unknown = state.keys - STATE - READS
        raise ArgumentError, "unknown looting state: #{unknown.join(', ')}" unless unknown.empty?

        @settings = settings
        @say = say
        @save = save
        @unlootable = unlootable
        @stow = stow || EO::Stow.new(learned: method(:learn))
        @disk_full = {}
        @checked_bags = []
        @sell_containers = []
        @weapon_inv = []
        state.each { |name, value| public_send(:"#{name}=", value) }
      end

      # @param type [String] "info", "yellow", "debug"
      # @param text [String]
      # @return [void]
      def say(type: 'info', text: '')
        @say&.call(type: type, text: text)
      end

      # Write the settings back to wherever the caller keeps them.
      #
      # @return [void]
      def save
        @save&.call
      end

      # What a put taught the stow, kept the way eloot keeps it: a bag that
      # closes itself and an item that crumbles go in the settings' lists
      # for the next run.
      #
      # @param kind [Symbol] :auto_close, :crumbly or :unlootable
      # @param obj [GameObj]
      # @return [void]
      def learn(kind, obj)
        case kind
        when :auto_close
          (settings[:auto_close] ||= []).push(obj.name)
          say(type: 'info', text: " #{obj.name} must be an autocloser, adding to list.")
          save
        when :crumbly
          say(type: 'info', text: ' This item was crumbly, adding to list')
          (settings[:crumbly] ||= []).push(obj.name)
          save
        when :unlootable then @unlootable&.call(obj)
        end
      end
    end
  end
end
