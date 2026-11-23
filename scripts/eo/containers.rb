# frozen_string_literal: true

module EO
  # Containers: seeing that one is open and that Lich knows what is in it,
  # closing it, and reading contents the game does not refresh on its own.
  #
  # Lich lists a container among GameObj.containers, with its contents, once
  # the game has shown them; that is what "listed" means here. Lich's
  # inventory feed (Lich::Common::Inventory) knows more of what is carried:
  # whether a container is closed or locked, without opening it.
  #
  # Commands go through the running script's helpers (EO.use). The helpers
  # this needs: command(text, pattern, silent:, quiet:) answering the lines,
  # result(text, pattern) answering one line, and say(type:, text:).
  module Containers
    module_function

    # Every answer OPEN gets, including the ones that mean it was open already.
    OPEN = Regexp.union(
      /You throw back/i,
      /You open/i,
      /Oh no! It's already/i,
      /You pick at the knot/i,
      /already open/i,
      /is open already/i,
      /You unfasten/i,
      /You glance around suspiciously/i,
      /^What were you referring to\?/i,
      /^I could not find what you were referring to\./i,
      /You pull the long strips of leather/i,
      /With a flick of your wrist/i,
      /Sliding the lever on the side/i,
      /You rub your hand/i,
      /There doesn't seem to be any way/i,
      /(?:Roundtime:|\.\.\.wait) (\d+) [Ss]ec(?:onds)?\./i,
      /crumbles? and decays? away/,
      /crumbles? into a pile of dust/,
      /Myriad spectral moths pull a cloakwing/,
      /<exposeContainer|<container/i,
      /You undo each of the/,
      /stuffed with a variety of shredded up paper and cloth/
    )

    # Every answer LOOK IN gets.
    LOOK = Regexp.union(
      /Peering into the <a exist=.*? noun="toolkit">/i,
      /That is closed/i,
      /is shut too tightly to see its contents/i,
      /In the(.*?)you see/i,
      /In the(.*?):/i,
      /There is nothing/i,
      /You glance/i,
      /^Attached to a.*keyring/i,
      /.*?[.*?]:/i,
      /The <a exist="\d+" noun="\w+">[^<]+<\/a> has (?:an? <a exist="\d+" noun="\w+">[^<]+<\/a> |nothing )?in.*scabbard and (?:an? <a exist="\d+" noun="\w+">[^<]+<\/a> |nothing )?in.*scabbard\./i,
      /^I could not find what you were referring to\./i,
      /Hidden within the depths of a cloakwing moth greatcloak/,
      /<exposeContainer|<dialogData|<container/i,
      /stuffed with a variety of shredded up paper and cloth/,
      /As much as you'd like to open it, its not closed\./,
      # a neck sheath and a swordbelt's scabbards show nothing Lich can list
      /^Looking at the .*?, you notice:/i,
      /^The .+? has .+? in its left-hand scabbard and .+? in its right-hand scabbard\.$/i
    )

    CLOSE = Regexp.union(
      /You close .*/,
      /(?:That|It) is already closed/,
      /What were you referring to/,
      /seem to be any way to do that/,
      /You tie/,
      /You fasten the/
    )

    # A LOOK IN answer, after an OPEN, that shows there is nothing Lich will
    # list: empty, or a container whose contents the game never itemises.
    NOTHING_LISTED = /You glance|There is nothing|stuffed with a variety of shredded up paper and cloth|^Looking at the .*?, you notice:|^The .+? has .+? in its left-hand scabbard and .+? in its right-hand scabbard\.$/i

    # The same for a container whose contents were waited for and did not
    # come. Not the same list as NOTHING_LISTED.
    NOTHING_TO_WAIT_FOR = /The wide leather belt|You glance|There is nothing|stuffed with a variety of shredded up paper and cloth|Looking at the .*?, you notice:/i

    # @param container [GameObj]
    # @return [Boolean] whether Lich has the container's contents
    def listed?(container)
      GameObj.containers.keys.include?(container.id) && container.contents.is_a?(Array)
    end

    # Whether Lich's inventory feed has answered this session. Once it has,
    # every carried container's contents are in GameObj, a closed one's too:
    # being listed no longer shows a container is open.
    #
    # @return [Boolean]
    def feed?
      defined?(Lich::Common::Inventory) && !Lich::Common::Inventory.last_updated.nil? ? true : false
    rescue StandardError
      false
    end

    # What the feed last said of a container, without asking again.
    #
    # @param container [GameObj]
    # @return [Boolean, nil] closed or not; nil when the feed has not
    #   answered or does not know the container (a disk, a box on the floor)
    def closed?(container)
      return nil unless feed?

      item = Lich::Common::Inventory[container.id]
      item.nil? ? nil : item.closed?
    rescue StandardError
      nil
    end

    # The feed's fresh view of a carried container: closed or not, locked
    # or not, with its contents put in GameObj either way.
    #
    # @param container [GameObj]
    # @return [Lich::Common::Inventory::Item, nil] nil without the feed, or
    #   for a container that is not carried (a disk, a box on the floor)
    def carried(container)
      return nil unless defined?(Lich::Common::Inventory)

      Lich::Common::Inventory.refresh&.[](container.id)
    rescue StandardError
      nil
    end

    # See that a container is open and its contents known. A carried one
    # is asked of the inventory feed: it gets an OPEN only when it is closed,
    # never a LOOK IN, and nothing at all when it is locked. Any other, or
    # without the feed: one already listed is left alone, and one that is
    # not is taken for closed, so it gets an OPEN and then a LOOK IN.
    #
    # @param container [GameObj]
    # @return [Symbol] :listed (open and known, nothing sent), :locked,
    #   :nothing (opened, and empty or not itemised), or :opened
    def ensure_open(container)
      if (item = carried(container))
        return :listed unless item.closed?
        return :locked if item.locked?

        EO.command("open ##{container.id}", OPEN, silent: true, quiet: true)
        return :opened
      end
      return :listed if listed?(container)

      EO.command("open ##{container.id}", OPEN, silent: true, quiet: true)
      lines = EO.command("look in ##{container.id}", LOOK, silent: true, quiet: true)
      lines.any? { |l| l =~ NOTHING_LISTED } ? :nothing : :opened
    end

    # Wait for Lich to have a container's contents, looking in once more when
    # they do not come.
    #
    # @param container [GameObj]
    # @param seconds [Numeric] how long each of the two waits lasts
    # @param from [String, nil] who asked, for the messages when it fails
    # @return [Boolean] false when the contents never came
    def contents_ready?(container, seconds: 3, from: nil)
      tenths = seconds * 10
      tenths.times do
        return true if listed?(container)
        sleep 0.1
      end
      EO.say(type: 'info', text: "This failed the first time. Trying again. | Container: #{container.name} | GameObj.containers.keys: #{GameObj.containers.keys.include?(container.id)} | container.contents.is_a?: #{container.contents.is_a?(Array)} | caller: #{from}")

      # goofy things happen: ask once more
      lines = EO.command("look in ##{container.id}", LOOK, silent: true, quiet: true)
      tenths.times do
        return true if listed?(container)
        return true if lines.any? { |l| l =~ NOTHING_TO_WAIT_FOR }
        sleep 0.1
      end
      EO.say(type: 'info', text: "This failed the second time. | Container: #{container.inspect} | caller: #{from}")
      EO.say(type: 'info', text: " Unable to determine the contents of  #{container.name}.")
      false
    end

    # Lich only updates a container's contents when the game sends a
    # refresh, and some containers never get one (a disk, a skin sack the
    # furrier emptied), so what Lich holds can still list what has since been
    # taken out. Look in, then read. A carried container is read from the
    # inventory feed instead, which asks the game afresh.
    #
    # @param container [GameObj, nil]
    # @return [Array<GameObj>] the contents, [] with no container
    def fresh_contents(container)
      return [] if container.nil?
      return container.contents.to_a if carried(container)

      EO.command("look in ##{container.id}", LOOK, silent: true, quiet: true)
      container.contents.to_a
    end

    # @param container [GameObj]
    # @return [String, nil] the game's answer
    def close(container)
      EO.result("close ##{container.id}", CLOSE)
    end
  end
end
