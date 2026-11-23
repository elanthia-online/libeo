# frozen_string_literal: true

module EO
  module Guild
    # When a task is done enough to stop hunting and go to town: a Rule the
    # driver evaluates with what the game says now (a driver that needs a
    # string to eval wraps the call), and the skin and gem counting that
    # goes with it.
    module Completion
      module_function

      # The task text when it is over, one way or another.
      DONE = /^You.*?(succeeded|located|failed )|your task is failed/

      # No task held.
      NO_TASK = /^You are not currently assigned /

      # A rescue task once the child has been found.
      CHILD_CONTACT = /^You have made contact with the child/

      # What the task calls a skin, as the item in a container is named:
      # singular, and the few plurals that are not an s.
      #
      # @param skin [String]
      # @return [String]
      def skin_name(skin)
        skin.to_s.strip.downcase.sub(/s$/, '').gsub(/teeth/, 'tooth').gsub(/hooves?/, 'hoof').gsub(/ruffs?/, 'ruff')
      end

      # The last two words of the skin name, which is how a bundle of them reads.
      #
      # @param skin [String]
      # @return [String, nil]
      def bundle_name(skin)
        m = skin.to_s.match(/(\w+)\s+(\w+)\s*\Z/)
        m && m[0].strip
      end

      # Skins held: loose ones by name, plus the contents of a bundle of
      # them, counted with MEASURE. A bundle is not measured while hidden,
      # since MEASURE would break the hiding; with a BundleTally it is
      # measured once and then counted as skins are added to it, hidden or
      # not, without a MEASURE every check.
      #
      # @param containers [Array<GameObj>]
      # @param skin [String] as the task names it
      # @param hidden [Boolean]
      # @param tally [BundleTally, nil]
      # @return [Integer]
      def skins_held(containers, skin, hidden: false, tally: nil)
        single = skin_name(skin)
        bundle = bundle_name(skin)
        loose = 0
        bundles = []
        containers.each do |container|
          container.contents.to_a.each do |item|
            if bundle && item.name =~ /bundle of #{Regexp.escape(bundle)}/
              bundles << item
            elsif !single.empty? && item.name =~ /#{Regexp.escape(single)}/i
              loose += 1
            end
          end
        end
        loose + bundled(bundles, hidden: hidden, tally: tally)
      end

      # @api private
      def bundled(bundles, hidden:, tally:)
        return 0 if bundles.empty?
        return tally.total if tally&.known?
        return (tally ? tally.total : 0) if hidden

        count = bundles.sum { |b| measure(b) }
        tally&.measured!(count)
        count
      end

      # A bundle's count kept between MEASUREs: the last MEASURE, plus one
      # for each skin the game says went into the bundle since ("You
      # carefully add your triton hide to your bundle of triton hides
      # inside ..."). Install it for the hunt and remove it after.
      class BundleTally
        ADDED = /You carefully add your .+? to your bundle of (.+?) inside/

        attr_reader :added

        # @param skin [String] the task's skin
        def initialize(skin)
          @bundle = Completion.bundle_name(skin).to_s.downcase
          @base = nil
          @added = 0
          @hook = "eo_bundle_tally_#{object_id}"
        end

        # @return [Boolean] whether a MEASURE has given the base yet
        def known? = !@base.nil?

        # @return [Integer] the last MEASURE plus the skins added since
        def total = @base.to_i + @added

        # A fresh MEASURE: the base, and the adds counted from here.
        #
        # @param count [Integer]
        def measured!(count)
          @base = count
          @added = 0
        end

        # Count a game line, when it adds one of these skins to the bundle.
        #
        # @param line [String]
        # @return [void]
        def see(line)
          @added += 1 if line =~ ADDED && Regexp.last_match(1).downcase.include?(@bundle)
        end

        # @return [void]
        def install
          tally = self
          DownstreamHook.add(@hook, proc do |line|
            tally.see(line.to_s.gsub(/<[^>]*>/, ''))
            line
          end)
        end

        # @return [void]
        def remove = DownstreamHook.remove(@hook)
      end

      # @param item [GameObj] a bundle
      # @return [Integer] how many it holds, from MEASURE
      def measure(item)
        lines = Lich::Util.quiet_command_xml("measure ##{item.id}", /You glance through/)
        lines.sum { |l| l.scan(/count a total of (\d+) <a exist/).flatten.map(&:to_i).sum }
      end

      # Gems held whose name ends with the task's gem.
      #
      # @param containers [Array<GameObj>]
      # @param gem [String] as the task names it ("an uncut diamond")
      # @return [Integer]
      def gems_held(containers, gem)
        name = gem.to_s.sub(/^an? /, '').strip
        return 0 if name.empty?
        containers.sum { |c| c.contents.to_a.count { |item| item.name =~ /#{Regexp.escape(name)}$/i } }
      end

      # The rule for one task. Built once when the hunt starts; asked each
      # tick with the game's current state.
      #
      # mind_needed: the mind percent the task text must be matched with for
      # an ordinary task (100, or the fried setting under exp_pause). A
      # bandit task ignores mind. count_mind: the mind percent a skin or gem
      # count must be matched with (the fried setting capped at 100).
      # keep_hunting: an ordinary task is not done while the mind is saturated.
      class Rule
        attr_reader :type, :number, :skin, :gem, :tally

        # @param task [Lich::Gemstone::Bounty::Task, nil] the task held, or nil
        # @param mind_needed [Integer]
        # @param count_mind [Integer]
        # @param extra_skin [Integer] skins to gather beyond the task's number
        # @param keep_hunting [Boolean]
        # @param tally [BundleTally, nil] counts a skin bundle between MEASUREs
        def initialize(task:, mind_needed: 100, count_mind: 100, extra_skin: 0, keep_hunting: false, tally: nil)
          @type = task&.type
          need = task&.requirements || {}
          @number = need[:number].to_i
          @skin = need[:skin]
          @gem = need[:gem]
          @mind_needed = mind_needed
          @count_mind = count_mind
          @extra_skin = extra_skin.to_i
          @keep_hunting = keep_hunting
          @tally = tally
        end

        # @param bounty_text [String] what BOUNTY says now
        # @param mind_percent [Numeric] the hunter's mind
        # @param bandit [Boolean] hunting bandits (the task text alone ends it)
        # @param saturated [Boolean] the mind is saturated
        # @param cooldown [Boolean] the Next Bounty cooldown is running
        # @param containers [Array<GameObj>] where skins and gems are kept
        # @param npcs [Array<GameObj>] who is in the room (the rescued child)
        # @param hidden [Boolean]
        # @return [Boolean]
        def complete?(bounty_text:, mind_percent:, bandit: false, saturated: false, cooldown: false,
                      containers: [], npcs: [], hidden: false)
          text = bounty_text.to_s
          return true if text =~ NO_TASK && !cooldown
          if text =~ DONE
            return true if bandit
            return true if mind_percent >= @mind_needed && !(@keep_hunting && saturated)
          end
          case @type
          when :rescue
            text =~ CHILD_CONTACT && npcs.any? { |npc| npc.name.to_s =~ /\bchild\b/ } ? true : false
          when :skin
            mind_percent >= @count_mind && Completion.skins_held(containers, @skin, hidden: hidden, tally: @tally) >= @number + @extra_skin
          when :gem
            mind_percent >= @count_mind && Completion.gems_held(containers, @gem) >= @number
          else
            false
          end
        end
      end
    end
  end
end
