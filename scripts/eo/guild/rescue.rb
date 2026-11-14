# frozen_string_literal: true

module EO
  module Guild
    # Rescue tasks: finding the child, where it lives, walking it to a guard
    # with a disabler ready for whatever shows up, and the two things that
    # go wrong when another script does the walk.
    module Rescue
      module_function

      # Who takes the child at a dropoff.
      REPORTEE = /sergeant|guard|purser|Belle|Luthrek/i

      # Where the child says it lives, to that town's square. River's Rest
      # and Solhaven answer with their county and barony.
      HOMES = {
        'Icemule Trace'        => 'u4042150',
        'Kharam Dzu'           => 'u3001025',
        'Kharam-Dzu'           => 'u3001025',
        "Kraken's Fall"        => 'u7118221',
        'Mist Harbor'          => 'u3201029',
        'the County of Torre'  => 'u2101008',
        'Vornavis'             => 'u4209030',
        "Ta'Illistim"          => 'u13100042',
        "Ta'Vaalor"            => 'u14100047',
        "Wehnimer's Landing"   => 'u7120',
        "Kharag 'doth Dzulthu" => 'u13006016',
      }.freeze

      # Ta'Vaalor's guards carry no advguard tag; these rooms are them.
      VAALOR_DROPOFF_UIDS = [4564003, 4564004, 4564010, 4564005, 4564011, 4564008, 4564006, 4564007, 4564013, 4564014, 4564009].freeze

      CHILD_ANSWER = /The child says, "Please, take me home to ([^!]+?)!"/
      TASK_FAILED = /^\[You have failed your current Adventurer's Guild task\.\]/

      # Maaghara Labyrinth: a child found inside has to be climbed out by a
      # root; when a root will not take us, the next exit room is tried.
      MAAGHARA_EXITS = {
        13022005 => 13022015, 13022025 => 13022015, 13022015 => 13022035,
        13022035 => 13022045, 13022045 => 13022005,
      }.freeze
      MAAGHARA_OUT_UID = 13021008

      # Rooms a child gets stuck on the way into, by uid, and the seconds to
      # wait there before going back a room, which sets the child moving
      # again. Kraken's Fall's Logging Colony: the log from the river leaves
      # the child on it.
      STALLS = { 589001 => 60 }.freeze
      ROOT_UP = /rootlike tendrils as thick as your thumb snake out and encircle/
      ROOT_REFUSED = /seem to be any way to do that at the moment/
      ROOT_SLIPPED = /You step into the root, but can see no way to climb the slippery tendrils inside\.  After a moment, you step back out\./

      # @return [Boolean] whether a child is in the room
      def child_here?
        GameObj.npcs.any? { |n| n.name =~ /child/i }
      end

      # @param bounty_text [String]
      # @return [Boolean] whether the task says the child has been contacted
      def contact?(bounty_text)
        bounty_text.to_s =~ /^You have made contact with the child you are to rescue/ ? true : false
      end

      # The child in the room, waiting a little for it to appear.
      #
      # @param noun [String] what to look for ("child"; a test can name a familiar)
      # @param timeout [Numeric] seconds
      # @return [String, nil] the child's id
      def find_child(noun: 'child', timeout: 5)
        deadline = Time.now + timeout
        loop do
          npc = GameObj.npcs.to_a.find { |n| n.noun =~ /#{noun}/i }
          return npc.id if npc
          return nil if Time.now > deadline
          sleep 0.1
        end
      end

      # The rooms a child can be handed over in, nearest first from +from+:
      # every advguard and advguard2 room plus Ta'Vaalor's.
      #
      # @param from [Room]
      # @return [Array<Integer>]
      def dropoffs(from: Map.current)
        tagged = from.find_all_nearest_by_tag('advguard') | from.find_all_nearest_by_tag('advguard2')
        (tagged | VAALOR_DROPOFF_UIDS.map { |uid| Map.ids_from_uid(uid).first }).compact
      end

      # Ask the child where home is.
      #
      # @return [Room, nil] that town's square, nil when it did not say or the
      #   place is unknown (a message says to report it)
      def home
        line = dothistimeout('ask child about destination', 5, CHILD_ANSWER)
        return nil unless line =~ CHILD_ANSWER
        uid = HOMES[Regexp.last_match(1)]
        if uid.nil?
          Lich::Messaging.msg('error', "missing child home entry for [#{Regexp.last_match(1)}], please report to elanthia-online.")
          return nil
        end
        Room[uid]
      end

      # The dropoff to walk to: the one nearest the child's home, or the
      # one nearest a room the caller names, or the nearest from here.
      #
      # @param near [Integer, String, nil] a room id or uid the caller chose
      # @param points [Array<Integer>] from .dropoffs
      # @return [Integer]
      def destination(points, near: nil)
        from = near ? Room[near] : home
        (from || Map.current).find_nearest(points)
      end

      # The walk: one step at a time, waiting for the child to follow, with
      # a disabler on anything hostile met on the way; at a dropoff with no
      # one to report to, on to the next. #run is the whole walk; a driver
      # with its own loop calls #start, then #step until it says
      # :delivered or :failed, then #finish, and can act between steps.
      class Walk
        # @param child [String] the child's GameObj id
        # @param to [Integer] the first dropoff
        # @param points [Array<Integer>] every dropoff, the chosen one included
        # @param disablers [Disablers::Policy]
        # @param step [String] the step script ("move2")
        def initialize(child:, to:, points:, disablers:, step: 'move2')
          @child = child
          @place = to
          @original = to
          @points = points - [to]
          @policy = disablers
          @step = step
          @can_disable = disablers.enabled && Disablers.any?(disablers)
          Lich::Messaging.msg('info', 'Note: No disablers known') if disablers.enabled && !@can_disable
          @stop_1011 = false
          @failed = false
        end

        # @return [Symbol] :delivered, or :failed when the task failed on the way
        #   (the walk goes back to where it was headed)
        def run
          start
          loop do
            result = step
            return result if %i[delivered failed].include?(result)

            sleep 0.1 if result == :waiting
          end
        ensure
          finish
        end

        # Before the first step: where the child was last seen, and the
        # watch for the task failing on the way.
        #
        # @return [void]
        def start
          $child_last_seen = Map.current.id
          @waiting = false
          Watchfor.new(TASK_FAILED) { @failed = true }
        end

        # One step of the walk.
        #
        # @return [Symbol] :moved (a room on, a disabler cast if one was
        #   wanted), :waiting (the child has not caught up), :unstuck (back a
        #   room from a STALLS room the child did not reach), :next_guard (no
        #   one to report to here; on to the next dropoff), :delivered, or
        #   :failed (the task failed; back to where the walk was headed)
        def step
          return fail! if @failed
          if @waiting
            return unstick if stalled?
            return :waiting unless child_here? || @waited_in != Map.current.id

            @waiting = false
            $child_last_seen = Map.current.id if child_here?
          end
          return arrive if Map.current.id == @place

          @came_from = Map.current.id
          move
          return fail! if @failed

          disable_hostiles
          @waiting = true
          @waited_in = Map.current.id
          @waited_at = Time.now
          :moved
        end

        # After the walk, however it ended: the watch off, 1011 stopped.
        #
        # @return [void]
        def finish
          # Lich keeps a script's watchfors by pattern; Watchfor has no delete
          Script.current&.watchfor&.delete(TASK_FAILED)
          return unless @stop_1011

          @stop_1011 = false
          waitrt?
          fput 'stop 1011'
        end

        # @return [Boolean] whether the child is in the room
        def child_here?
          GameObj.npcs.to_a.any? { |n| n.id == @child }
        end

        private

        # Waiting in a stall room past its time, the child not here.
        def stalled?
          limit = STALLS[Map.current.uid.to_a.first.to_i]
          !limit.nil? && !child_here? && @waited_in == Map.current.id && Time.now - @waited_at >= limit
        end

        # Back to the room before, and on again from there: the child,
        # stuck on the way in, moves when we do.
        #
        # @return [Symbol] :unstuck
        def unstick
          EO.go2(@came_from)
          @waiting = false
          :unstuck
        end

        def fail!
          EO.go2(@original)
          :failed
        end

        # At the dropoff: the child handed over, or on to the next one.
        def arrive
          npc = reportee
          if npc.nil?
            @place = Map.current.find_nearest(@points)
            @points.delete(@place)
            return :next_guard
          end
          fput "ask ##{npc.id} about bounty"
          $child_last_seen = nil
          :delivered
        end

        # One room toward the place, by the step script.
        def move
          climb_root if MAAGHARA_EXITS.key?(Map.current.uid.to_a.first.to_i)
          from = Map.current.id
          waitrt?
          Script.run(@step, @place.to_s)
          wait_while { running?(@step) }
          wait_until { from != Map.current.id || @failed }
          waitrt?
        end

        # @return [GameObj, nil] someone to hand the child to, here
        def reportee
          GameObj.npcs.to_a.find { |n| n.name =~ REPORTEE } || GameObj.room_desc.to_a.find { |n| n.name =~ REPORTEE }
        end

        # A disabler on hostile creatures, unless players or a reportee are
        # here, or only the child is.
        def disable_hostiles
          return unless @can_disable
          return if checkpcs
          return if GameObj.npcs.to_a.any? { |n| n.name =~ REPORTEE } || GameObj.room_desc.to_a.any? { |n| n.name =~ /purser/ }
          return unless GameObj.targets.to_a.any? { |npc| !@policy.untargetable.include?(npc.name) }
          return if GameObj.npcs.to_a.size == 1 && GameObj.npcs.to_a.first.id == @child
          return unless Disablers.target!(@policy)
          num = Disablers.best(@policy)
          return if num.nil?
          @stop_1011 = true if num == 1011
          Disablers.cast!(num)
        end

        # GO ROOT, up to three tries; when a root refuses, head for the next
        # exit room instead; when it takes us, the original place is back on.
        def climb_root
          3.times do
            result = dothistimeout('go root', 3, Regexp.union(ROOT_UP, ROOT_REFUSED, ROOT_SLIPPED))
            case result
            when ROOT_UP
              @place = @original
              wait_while { Map.current.uid.to_a.first.to_i != MAAGHARA_OUT_UID }
              EO.stand
              return
            when ROOT_REFUSED
              here = Map.current.uid.to_a.first.to_i
              @place = Map.ids_from_uid(MAAGHARA_EXITS[here]).first if MAAGHARA_EXITS.key?(here)
              return
            when ROOT_SLIPPED
              sleep 1
              redo
            else
              Lich::Messaging.msg('warn', 'climbing the root failed')
            end
          end
        end
      end

      # Walk the child to a guard. See Walk.
      #
      # @return [Symbol] :delivered or :failed
      def escort(child:, to:, points:, disablers:, step: 'move2')
        Walk.new(child: child, to: to, points: points, disablers: disablers, step: step).run
      end

      # Run a rescue script from the child's room. A garrote during the walk
      # leaves the child behind: heal, come back, run it again. A Bard's Song
      # of Peace is stopped after, since it blocks the walk.
      #
      # @param script [String] the rescue script ("echild")
      # @param heal [Proc] what to do about a cutthroat before returning
      # @return [void]
      def run(script, heal:)
        Script.run(script)
        sleep 2
        kill_script('go2') if running?('go2')

        if child_here? && cutthroat?
          room = Room.current.id
          heal.call
          EO.go2(room)
          Script.run(script)
          sleep 2
        end

        return unless Stats.prof == 'Bard'
        lines = EO.command('spell active', /<dialogData id='Active Spells'/, silent: true, quiet: true)
        fput 'stop 1011' if lines.any? { |l| l =~ /Song of Peace/ }
      end
    end
  end
end
