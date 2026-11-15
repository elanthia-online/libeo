# frozen_string_literal: true

module EO
  module Guild
    # The taskmaster: asking for a task, turning one in, having one
    # removed or expedited; and the boosts and vouchers a character has.
    #
    # Commands, waits and messages go through the running script's helpers
    # (EO.use). The helpers this needs: command(text, pattern, silent:,
    # quiet:) answering the lines, wait(), and say(type, text).
    module Taskmaster
      module_function

      # Rounds of asking before giving up.
      ATTEMPTS = 5

      # What is asked for each purpose, how many times in a round, and
      # whether the asking is done once a task is held (else once none is).
      ASKS = {
        'get'      => { about: 'bounty', times: 1, until_task: true },
        'turn-in'  => { about: 'bounty', times: 1, until_task: false },
        'remove'   => { about: 'removal', times: 2, until_task: false },
        'expedite' => { about: 'expediting', times: 2, until_task: true },
        'failure'  => { about: 'bounty', times: 1, until_task: false }
      }.freeze

      # Whether the task's text changes within three seconds.
      #
      # @param original [String] the text before
      # @return [Boolean]
      def changed?(original)
        end_wait = Time.now + 3

        until Time.now > end_wait
          return true if checkbounty != original

          sleep 0.2
        end

        false
      end

      # @return [Boolean] whether BOOST INFO shows a bounty boost to use
      def boosts?
        lines = EO.command('boost info', /<a exist=".*?" noun=".*?">.*?<\/a>, your Login Rewards information is as follows/, silent: true, quiet: true)
        boost = Regexp.last_match(1).delete(',').to_i if lines.any? { |l| l =~ /<d cmd='boost bounty'>Bounty Boosts<\/d>:\s+([0-9,]+)/ }
        boost&.positive? ? true : false
      end

      # @return [Boolean] whether BOUNTY shows a reassignment voucher to use
      def vouchers?
        lines = EO.command('bounty', /<a exist=".*?" noun=".*?">.*?<\/a>, your Adventurer's Guild information is as follows/, silent: true, quiet: true)
        voucher = Regexp.last_match(1).delete(',').to_i if lines.any? { |l| l =~ /You have ([0-9,]+) expedited task reassignment vouchers remaining/ }
        voucher&.positive? ? true : false
      end

      # Ask the taskmaster, round after round, until a task is held or none
      # is, as the purpose has it. A round whose asking leaves the task's
      # text unchanged, or that fails in any way, is tried again.
      #
      # @param type [String] a key of ASKS
      # @param boost_type [String, nil] for 'get', the kind of task to ask
      #   for while a bounty boost runs
      # @return [Symbol] :done; :already_assigned (a task is already held);
      #   :ready (an expedite answered with a new offer); :no_taskmaster (he
      #   could not be found); or :gave_up after ATTEMPTS rounds
      def ask(type, boost_type: nil)
        spec = ASKS.fetch(type)
        about = type == 'get' ? "bounty #{boost_type || ''}" : spec[:about]
        ask_count = spec[:times]
        attempts = 0
        original = checkbounty

        begin
          attempts += 1

          until spec[:until_task] ? Bounty.type != :none : Bounty.type == :none
            npc = NPCs.taskmaster
            return :no_taskmaster if npc.nil?

            ask_count.times do
              result = fput "ask #{npc} about #{about}"
              if result =~ /Who are you trying to ask/
                npc = NPCs.taskmaster
                return :no_taskmaster if npc.nil?
              elsif result =~ /You have already been assigned a task/
                return :already_assigned
              elsif result =~ /I'm ready to assign you a new task/ && type.eql?('expedite')
                return :ready
              end
              EO.settle
            end

            raise 'Bounty did not change' unless changed?(original)
          end
          :done
        rescue StandardError
          return :gave_up unless attempts < ATTEMPTS

          EO.say('yellow', "Bounty type did not change, retrying (attempt #{attempts})...")
          ask_count = 1
          retry
        end
      end
    end
  end
end
