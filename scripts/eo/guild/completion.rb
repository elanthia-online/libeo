# frozen_string_literal: true

module EO
  module Guild
    # When a task is done enough to go back to town, and counting what a
    # skin or gem task has gathered so far.
    #
    # Commands go through the running script's helpers (EO.use). The helper
    # this needs: command(text, pattern) answering the lines.
    module Completion
      module_function

      # A task that asks for a child to be found.
      CHILD_TASK = /A local divinist has had visions of the child fleeing/
      # A task that asks for skins, and its count and skin.
      SKIN_TASK = /You have been tasked to retrieve(.*)of at least/
      SKIN_COUNT = /You have been tasked to retrieve (\d+) (.*?)(?:s)? of at/
      # A task that asks for gems.
      GEM_TASK = /The gem dealer/
      # The last two words of a skin's name, which a bundle is named by.
      BUNDLE_WORDS = /(\w+)\s+(\w+)\s*\Z/

      # The rule a hunting script is given to stop on, as Ruby for it to
      # evaluate each time round: the task done and the mind full enough,
      # a bandit task done, a new task on offer, and what the task at hand
      # adds. It is evaluated inside the hunting script, so it names that
      # script's own measures (@CORRECT_PERCENT_MIND, $bigshot_bandits) and
      # reads ebounty's data as it stands then.
      #
      # @param bounty [String] the task's text
      # @param exp_pause [Boolean] rest when the mind reaches the hunting
      #   script's own limit
      # @param keep_hunting [Boolean] hunt on while the mind is not saturated
      # @param bundle_skin [Object] what a skin task's bundle is named by
      # @param skin [String, nil] the skin a task wants
      # @param gem [String, nil] the gem a task wants
      # @return [String]
      def rule(bounty, exp_pause:, keep_hunting:, bundle_skin: nil, skin: nil, gem: nil)
        text = if exp_pause
                 %Q{!!(checkbounty =~ /^You.*?(succeeded|located|failed )|your task is failed/ && !$bigshot_bandits && @CORRECT_PERCENT_MIND >= UserVars.op['fried'].to_i)}
               elsif keep_hunting
                 %Q{!!(checkbounty =~ /^You.*?(succeeded|located|failed )|your task is failed/ && checkmind != 'saturated' && !$bigshot_bandits && @CORRECT_PERCENT_MIND >= 100)}
               else
                 %Q{!!(checkbounty =~ /^You.*?(succeeded|located|failed )|your task is failed/ && !$bigshot_bandits && @CORRECT_PERCENT_MIND >= 100)}
               end

        text += %Q{ || !!(checkbounty =~ /^You.*?(succeeded|located|failed )|your task is failed/ && $bigshot_bandits)}
        text += %Q{ || !!(checkbounty =~ /^You are not currently assigned / && !Effects::Cooldowns.to_h.include?('Next Bounty'))}

        if bounty =~ CHILD_TASK
          text += %Q{ || !!(checkbounty =~ /^You have made contact with the child/ && GameObj.npcs.any? { |npc| npc.name =~ /\\bchild\\b/ })}
        elsif bounty =~ SKIN_TASK
          text += %Q{ || !!(count = 0;EBounty.data.containers.each{|i| i.contents.each{ |k| if k.name =~ /bundle of #{bundle_skin}/ && !EBounty.data.bundle_skin.to_s.empty? && !hidden?; lines = Lich::Util.quiet_command_xml("measure #"+k.id.to_s, /You glance through/);count += lines.sum { |l| l.scan(/count a total of (\\d+) <a exist/).flatten.map(&:to_i).sum };end;};};count >= EBounty.data.remaining_skins.to_i && @CORRECT_PERCENT_MIND >= EBounty.data.complete_mind)}
          text += %Q{ || !!(j=0;EBounty.data.containers.each{|i| j += i.contents.count{|l| l.name =~ /#{skin}/i && !EBounty.data.skin.to_s.empty?}.to_i }; j >= EBounty.data.remaining_skins.to_i && @CORRECT_PERCENT_MIND >= EBounty.data.complete_mind)}
        elsif bounty =~ GEM_TASK
          text += %Q{ || !!(t=0;EBounty.data.containers.each{|k| t += k.contents.count{|v| v.name =~ /#{gem.strip}$/i && !EBounty.data.gem.to_s.empty?}.to_i}; t>= EBounty.data.remaining_gems.to_i && @CORRECT_PERCENT_MIND >= EBounty.data.complete_mind)}
        end

        text
      end

      # What a skin task asks for, from its text.
      #
      # @param bounty [String]
      # @return [Array(Integer, String), nil] how many, and the skin as
      #   the task words it; nil when the text does not say
      def skin_wanted(bounty)
        return nil unless bounty =~ SKIN_COUNT

        [Regexp.last_match(1).to_i, Regexp.last_match(2)]
      end

      # A skin's name as items carry it: singular, and a few plurals that
      # are not made with an s.
      #
      # @param skin [String] the skin as the task words it
      # @return [String]
      def skin_name(skin)
        skin.strip.downcase
            .gsub(/s$/, '')
            .gsub(/teeth/, 'tooth')
            .gsub(/hooves?/, 'hoof')
            .gsub(/ruffs?/, 'ruff')
      end

      # Count the skins held for a task: those in a bundle, by measuring
      # it, and each loose one.
      #
      # @param containers [Array<GameObj>]
      # @param bundle_skin [Object] what the bundle is named by
      # @param skin [String] from skin_name
      # @param open [Proc] given a container, sees it open
      # @return [Integer]
      def skins_held(containers, bundle_skin, skin, open:)
        count = 0
        containers.each do |container|
          open.call(container)
          container.contents.each do |item|
            if item.name =~ /bundle of #{bundle_skin}/
              lines = EO.command("measure ##{item.id}", /You glance through/)
              lines.each { |l| count += Regexp.last_match(1).to_i if l =~ /count a total of (\d+) <a exist/ }
            elsif item.name =~ /#{skin}/
              count += 1
            end
          end
        end
        count
      end

      # Count the gems held for a task.
      #
      # @param containers [Array<GameObj>]
      # @param gem [String] the gem, as its name ends
      # @param open [Proc] given a container, sees it open
      # @return [Integer]
      def gems_held(containers, gem, open:)
        count = 0
        containers.each do |container|
          open.call(container)
          container.contents.each { |item| count += 1 if item.name =~ /#{gem}$/ }
        end
        count
      end

      # How long until the experience over the mind's limit is absorbed,
      # by a guess at what a pulse absorbs: 25, a fifth of the Logic bonus,
      # 2 for a supernode, a two-hundredth of the experience held (10 at
      # most), and 1 for a group.
      #
      # @return [Integer] minutes
      def minutes_to_absorb
        experience = Lich::Gemstone::Experience
        extra_exp = [experience.fxp_current - experience.fxp_max, 0].max
        absorption = 25 + (Stats.enhanced_log[1] / 5) + 2 + [experience.fxp_current / 200, 10].min + 1

        # a pulse every two minutes
        ((extra_exp / absorption) * 120) / 60
      end
    end
  end
end
