# frozen_string_literal: true

module EO
  module Cleanse
    # Things in a room that hurt or hinder: webs, magical globes and clouds,
    # runestones. Each is got rid of by a spell, by Spell Cleave or Spell
    # Thieve, or by hitting it.
    module Hazards
      module_function

      # @return [Boolean] Spell Cleave can be used now
      def cleave? = CMan.available?('Spell Cleave')

      # @return [Boolean] Spell Thieve can be used now
      def thieve? = CMan.available?('Spell Thieve')

      # Get rid of a web, globe or cloud by the first means there is: the
      # spell, after a mana pulse when it cannot be afforded; else Spell
      # Cleave; else Spell Thieve.
      #
      # @param obj [GameObj] the hazard
      # @param spell [Spell, nil] the spell for it, nil when the character
      #   has none or cannot cast now
      # @return [void]
      def clear(obj, spell)
        if spell
          Lich::Gemstone::Mana.pulse(spell.num)
          spell.cast("at ##{obj.id}") if spell.affordable?
        elsif cleave?
          CMan.use('Spell Cleave', "##{obj.id}")
        elsif thieve?
          CMan.use('Spell Thieve', "##{obj.id}")
        end
      end

      # Blow away a cloud of acidic mist: Call Wind (912) by incantation, or
      # Breeze (612) cast at it.
      #
      # @param cloud [GameObj]
      # @param breeze [Spell] 912 or 612
      # @return [void]
      def blow_away(cloud, breeze)
        breeze.force_incant if breeze.num.eql?(912)
        breeze.cast("at ##{cloud.id}") if breeze.num.eql?(612)
      end

      # Hit a runestone until it shatters, it is gone, or five swings are made.
      #
      # @param runestone [GameObj]
      # @return [void]
      def shatter(runestone)
        attempts = 0
        loop do
          waitrt?
          results = Lich::Util.issue_command("attack ##{runestone.id}", /You bash/, /Roundtime: /, timeout: 2, usexml: false, quiet: false, silent: false)
          attempts += 1
          break if results.any? { |line| line =~ /It crashes to the ground and shatters into pale dust/ }
          break if attempts >= 5
          break unless GameObj.loot.map(&:id).include?(runestone.id)
        end
      end
    end
  end
end
