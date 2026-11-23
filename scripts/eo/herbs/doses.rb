# frozen_string_literal: true

module EO
  module Herbs
    # How many doses each herb and potion has left, learned from what the
    # game says as they are eaten, drunk, measured, bought and bundled. The
    # counts are kept by item id in $eherbs_measure, where other scripts
    # read them, and last for the session.
    module Doses
      # Reads the game's lines one at a time and keeps the counts. One is
      # made for a run of the script and its read method put on a
      # DownstreamHook.
      class Monitor
        def initialize
          # doses in what was just bought, for the bundle it goes into
          @doses = 0
          # the item being eaten or drunk, until the next prompt
          @using = nil
          @last_left_hand_id = nil
          $eherbs_measure ||= {}
        end

        # Read one line from the game.
        #
        # @param line [String]
        # @return [String] the line, unchanged
        def read(line)
          @last_left_hand_id = Regexp.last_match(1) if line =~ /<left exist="([0-9]+)"/
          if line =~ /<prompt/
            @using = nil
          elsif @using
            if line =~ /^You have only about ([0-9]+) quaffs left\./
              $eherbs_measure[@using] = Regexp.last_match(1).to_i
            elsif line =~ /^You have (?:about )?([0-9]+) (?:doses|bites) left\./
              $eherbs_measure[@using] = Regexp.last_match(1).to_i
            elsif line =~ /^You (?:only )?have one bite left\./
              $eherbs_measure[@using] = 1
            elsif line =~ /^You have only about one quaff left\.|You only have one (?:dose|quaff) left\./
              $eherbs_measure[@using] = 1
            elsif line =~ /^That was the last (?:drop|of it)\./
              $eherbs_measure[@using] = 0
            end
          elsif line =~ /^You take a (?:drink from|bite of) your .*? exist="([0-9]+)"/
            @using = Regexp.last_match(1)
          elsif line =~ /^You carefully pour a little bit from your .*? exist="([0-9]+)" .*? into .*? exist="([0-9]+)"/
            @using = Regexp.last_match(1)
            into = Regexp.last_match(2)
            $eherbs_measure[into] += 1 if $eherbs_measure[into]
          elsif line =~ /^The .*? exist="([0-9]+)" .*? has several doses left\./
            about(Regexp.last_match(1), 5..10, 7)
          elsif line =~ /^The .*? exist="([0-9]+)" .*? has a few doses left\./
            about(Regexp.last_match(1), 3..4, 4)
          elsif line =~ /^The .*? exist="([0-9]+)" .*? has ([0-9]+) doses left\./
            $eherbs_measure[Regexp.last_match(1)] = Regexp.last_match(2).to_i
          elsif line =~ /^The .*? exist="([0-9]+)" .*? has 1 dose left\./
            $eherbs_measure[Regexp.last_match(1)] = 1
          elsif line =~ /^You can't tell exactly, but .*? exist="(.*?)" .*? seems to have plenty of bites left\./
            about(Regexp.last_match(1), 11..50, 50)
          elsif line =~ /^The .*? exist="(.*?)" .*? looks like it has several bites left\./
            about(Regexp.last_match(1), 5..10, 10)
          elsif line =~ /^The .*? exist="(.*?)" .*? looks like it has a few bites left\./
            about(Regexp.last_match(1), 3..4, 4)
          elsif line =~ /^The .*? exist="(.*?)" .*? has ([0-9]+) bites left\./
            $eherbs_measure[Regexp.last_match(1)] = Regexp.last_match(2).to_i
          elsif line =~ /^The .*? exist="(.*?)" .*? has (?:one|1) bite left\./
            $eherbs_measure[Regexp.last_match(1)] = 1
          elsif line =~ /^(?:Sh|H)e hands you <a exist="[0-9]+".*?>(.*)<\/a> and says, "Here's your purchase\./
            bought = Regexp.last_match(1).dup
            found = Table::KNOWN.find { |h| h[:name] == bought }
            # a purchase the table does not have by that name counts as 4
            @doses = found ? found[:store_doses] : 4
          elsif line =~ /^Carefully, you combine all your .*? into one bundle\./
            bundle_id = GameObj.right_hand.id
            if $eherbs_measure[bundle_id] && !@doses.nil?
              $eherbs_measure[bundle_id] += @doses.to_i
              @doses = nil
            elsif ($eherbs_measure[bundle_id] && $eherbs_measure[bundle_id] > 10) || ($eherbs_measure[@last_left_hand_id] && $eherbs_measure[@last_left_hand_id] > 10)
              # the bundle has between 11 and 50 bites: say 50, so no more
              # is bought than can be bundled; using it finds the true count
              $eherbs_measure[bundle_id] = 50
              $eherbs_measure.delete(@last_left_hand_id)
            else
              # between 2 and 50: forget the counts, so the bundle gets measured
              $eherbs_measure.delete(bundle_id)
              $eherbs_measure.delete(@last_left_hand_id)
            end
          elsif line =~ /^You carefully remove one dose from your <a exist="([0-9]+)"/
            from = Regexp.last_match(1)
            $eherbs_measure[from] -= 1 if $eherbs_measure[from]
            $eherbs_measure[@last_left_hand_id] = 1
          end
          line
        end

        private

        # Set a count the game only described, unless one already held
        # agrees with the description.
        def about(id, range, guess)
          held = $eherbs_measure[id]
          $eherbs_measure[id] = guess if held.nil? || held < range.first || held > range.last
        end
      end
    end
  end
end
