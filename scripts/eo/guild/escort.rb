# frozen_string_literal: true

module EO
  module Guild
    # Escorting a client from one town to another: the task and its towns,
    # having the client follow, and the walk itself, which keeps the room
    # clear, hides and hastes before each move, takes the hard parts of the
    # road by its own routes (ROUTES) and goes back for a client who has
    # fallen behind.
    module Escort
      module_function

      # An escort task: where to wait for the client, and the town to reach.
      TASK = /client has hired us to provide a protective escort .* Go to the (.*?) and WAIT .* guarantee .*? safety to (.*?) as soon as you can/
      # An escort task still held.
      HELD = /client has hired us to provide a protective escort/
      # What a client is called.
      CLIENT_NOUN = /^(?:traveller|magistrate|merchant|scribe|dignitary|official)$/
      # Creatures of the road not worth stopping for.
      IGNORABLE = /^(?:kobold|rolton|urgh|ridge orc|hobgoblin|velnalin|fire ant)$/
      # A creature in no state to attack.
      DISABLED = /dead|sleeping|calm|stunned|lying down|prone|sitting|frozen/

      # Rooms where hiding is not tried, and where haste is not cast.
      NO_HIDE_ROOMS = [1156, 1155, 1154, 1153].freeze
      NO_HASTE_ROOMS = [1191].freeze

      # Where a task says to wait, as the town and the room.
      PICKUPS = {
        'area just inside the Sapphire Gate'                   => ["Ta'Illistim", 34],
        'area just inside the North Gate'                      => ["Wehnimer's Landing", 223],
        'south end of North Market'                            => ['Solhaven', 1472],
        'area just north of the South Gate, past the barbican' => ['Icemule Trace', 2412],
        "Kresh'ar Deep monument"                               => ['Zul Logoth', 1005],
        'area just inside the Amaranth Gate'                   => ["Ta'Vaalor", 3483]
      }.freeze

      # The rooms a client can be brought to, by town.
      DROPOFFS = {
        "Wehnimer's Landing" => [223],
        'Icemule Trace'      => [2412],
        'Zul Logoth'         => [992, 1266],
        'Solhaven'           => [3902],
        "Ta'Vaalor"          => [5907],
        "Ta'Illistim"        => [37]
      }.freeze

      # The silver a trip and the way back cost in fares, from a town to a
      # town.
      TRAVEL_COST = {
        "Wehnimer's Landing" => { 'Icemule Trace' => 0, 'Zul Logoth' => 20, 'Solhaven' => 0, "Ta'Vaalor" => 4020, "Ta'Illistim" => 4020 }.freeze,
        'Icemule Trace'      => { "Wehnimer's Landing" => 0, 'Zul Logoth' => 20, 'Solhaven' => 0, "Ta'Vaalor" => 4020, "Ta'Illistim" => 4020 }.freeze,
        'Zul Logoth'         => { "Wehnimer's Landing" => 2020, 'Icemule Trace' => 2020, 'Solhaven' => 2020, "Ta'Vaalor" => 2000, "Ta'Illistim" => 2000 }.freeze,
        'Solhaven'           => { "Wehnimer's Landing" => 0, 'Icemule Trace' => 0, 'Zul Logoth' => 20, "Ta'Vaalor" => 4020, "Ta'Illistim" => 4020 }.freeze,
        "Ta'Vaalor"          => { "Wehnimer's Landing" => 4020, 'Icemule Trace' => 4020, 'Zul Logoth' => 2000, 'Solhaven' => 4020, "Ta'Illistim" => 0 }.freeze,
        "Ta'Illistim"        => { "Wehnimer's Landing" => 4020, 'Icemule Trace' => 4020, 'Zul Logoth' => 2000, 'Solhaven' => 4020, "Ta'Vaalor" => 0 }.freeze
      }.freeze

      # Where a task says to wait and the town it names.
      #
      # @param text [String] the task, as BOUNTY gives it
      # @return [Array(String, String), nil] nil for a task that is not an escort
      def task(text)
        [Regexp.last_match(1), Regexp.last_match(2)] if text =~ TASK
      end

      # Come out of hiding and tell a client to follow.
      #
      # @param npc [GameObj]
      # @return [Boolean] whether this is the client, and follows
      def follow(npc)
        fput 'unhide' if hidden? or invisible?
        result = dothistimeout "tell ##{npc.id} to follow", 8, /#{npc.noun} nods and says to you|#{npc.noun} says to you, "But I already am!"|#{npc.noun} says to you, "The guild didn't hire you to guide me\."|^The merchant gives you a strange look\.$/
        result =~ /#{npc.noun} nods and says to you|#{npc.noun} says to you, "But I already am!"/ ? true : false
      end

      # @return [Boolean] whether the character has a wound or scar, or is
      #   down more than fifty health
      def hurt?
        ([Wounds.head, Wounds.neck, Wounds.torso, Wounds.limbs, Wounds.nerves, Scars.head, Scars.neck, Scars.torso, Scars.limbs, Scars.nerves].max > 0) or ((checkhealth + 50) < maxhealth)
      end

      # The room of a list quickest to reach.
      #
      # @param target_list [Array<Integer>] room ids
      # @return [Integer, nil] nil when none can be reached
      def nearest(target_list)
        start_room = Room.current
        if target_list.include?(start_room.id)
          nearest_id = start_room.id
        else
          _, shortest_distances = Map.dijkstra(start_room.id, target_list)
          nearest_id = least_time = nil
          for target in target_list
            est_time = shortest_distances[target]
            if !est_time.nil? and (least_time.nil? or least_time > est_time)
              nearest_id = target
              least_time = est_time
            end
          end
        end
        nearest_id
      end

      # In Platinum, take the portals out of the map for this session, so
      # no path is laid through one.
      #
      # @return [void]
      def close_portals
        if XMLData.game =~ /^GSPlat/ and not Map.list.any? { |room| room.timeto.any? { |_adj_id, time| time.class == Proc and time._dump =~ /$go2_use_portals/ } }
          for start_room in ['7561', '9318', '3479', '2696', '17691', '12584', '9664', '20453', '16746']
            for end_room in ['7561', '9318', '3479', '2696', '17691', '12584', '9664', '20453', '16746']
              if start_room != end_room
                Map[start_room.to_i].wayto.delete(end_room)
                Map[start_room.to_i].timeto.delete(end_room)
              end
            end
          end
          for start_room in ['7561', '5052', '9095', '2696', '11128', '12387', '648', '5766', '5940']
            for end_room in ['7561', '5052', '9095', '2696', '11128', '12387', '648', '5766', '5940']
              if start_room != end_room
                Map[start_room.to_i].wayto.delete(end_room)
                Map[start_room.to_i].timeto.delete(end_room)
              end
            end
          end
          for start_room in ['19706', '19709', '19745', '19752', '19778', '19723', '19721', '19719']
            Map[start_room.to_i].wayto.delete('19707')
            Map[start_room.to_i].timeto.delete('19707')
          end
        end
      end

      # The script to run beside an escort (start_exec_script), which
      # watches the game for an ambush sprung on this client. It sets
      # $ego2_my_ambush, and $ego2_staggered_ambush when the bandits arrive
      # one after another, and clears both in each new room. The client is
      # known to it by $ego2_escort_id.
      #
      # @param name [String] the escorting script, which it stops with
      # @return [String]
      def ambush_watch(name)
        <<~WATCH
          hide_me
          status_tags
          before_dying { kill_script(#{name.inspect}) if running?(#{name.inspect}) }
          Thread.new { wait_while { running?(#{name.inspect}) }; Script.self.kill }
          while (line = get)
            if line =~ /<pushStream id='room'/
              $ego2_my_ambush = false
              $ego2_staggered_ambush = false
              echo 'not my ambush' if $ego2_debug
            elsif line =~ /An? .*?\#{$ego2_escort_id}.*? fearfully exclaims, \"It's an ambush!\"|<compass>.*?(?:quickly approaches|suddenly leaps from|leaps out of|suddenly jumps out of the shadows)|carefully concealed metal jaws|nearly invisible length of razor wire|length of nearly invisible razor wire|carefully concealed inflated pouch|carefully concealed looped rope|a carefully concealed net|carefully concealed pit|Suddenly, the ground gives out from under you as you fall into a shallow pit filled with tiny spikes!/
              # removed cause it caused a poach: tiny shard of jet black crystal
              $ego2_my_ambush = true
              echo 'my ambush' if $ego2_debug
              if line =~ /<compass>.*?(?:quickly approaches|suddenly leaps from|leaps out of|suddenly jumps out of the shadows)/
                $ego2_staggered_ambush = true
                echo 'staggered ambush' if $ego2_debug
              end
            end
          end
        WATCH
      end

      # One escort's walk: its settings, the client, the path, and what has
      # been learned of the rooms passed through.
      #
      # The hard parts of the road are in ROUTES, each run as a part of
      # this walk.
      class Walk
        # @return [String, nil] the client's id
        attr_accessor :escort_id
        # @return [Room, nil] where the client is to be brought
        attr_accessor :destination
        # @return [Array<Integer>, nil] the rooms of the path being walked
        attr_reader :path

        # @param hide [Boolean] hide before moving
        # @param haste [Boolean] cast Haste (506) before moving
        # @param poach [Boolean] fight in a room other characters are in
        # @param attack_script [String, nil] the script to fight with; nil
        #   to pause for the player instead
        # @param targetable [Array<String>] names of creatures found to be
        #   targetable; added to
        # @param untargetable [Array<String>] names found not to be; added to
        def initialize(hide:, haste:, poach:, attack_script:, targetable:, untargetable:)
          @hide = hide
          @haste = haste
          @poach = poach
          @attack_script = attack_script
          @targetable = targetable
          @untargetable = untargetable
          @escort_id = nil
          @destination = nil
          @path = nil
          @justice = true
          @justice_count = 0
          @sanct_count = -1
        end

        # Hide, when hiding is wanted and this is a room for it.
        #
        # @return [void]
        def hide
          if @hide
            Spell.lock_cast
            unless hidden? or invisible? or NO_HIDE_ROOMS.include?(Room.current.id)
              waitrt?
              fput 'hide'
              sleep 0.5
              waitrt?
            end
          end
        end

        # Cast Haste (506), when it is wanted and is not up.
        #
        # @return [void]
        def haste
          if @haste
            spell = Spell[506]
            if not spell.active? and spell.known? and spell.affordable? and not NO_HASTE_ROOMS.include?(Room.current.id)
              spell.cast
            end
          end
        end

        # Cast Wizard's Shield (919) before a move that breaks hiding.
        #
        # @return [void]
        def protect
          # called for moves that knock you out of hiding, so it's pointless if hiding isn't enabled
          if @hide
            wizard_shield = Spell[919]
            if wizard_shield.known? and not wizard_shield.active? and (mana > 150)
              wizard_shield.cast
            end
          end
        end

        # @return [Boolean] whether the client is in the room
        def escort_here?
          GameObj.npcs.to_a.any? { |npc| npc.id == @escort_id }
        end

        # Deal with the room before going on. Creatures not met before are
        # tried with TARGET and remembered. Then, as long as there is
        # something to fight (creatures able to attack, or this escort's
        # own bandits, in a room nobody else has a claim on, or a character
        # who attacked where there is no justice), the attack script is run
        # against them, or the script pauses for the player. A room found
        # to be a sanctuary is left alone.
        #
        # @return [void]
        def check_room
          if @hide
            Spell.unlock_cast
          end
          loop {
            while (unknown_npc = GameObj.npcs.to_a.find { |npc| not @targetable.include?(npc.name) and not @untargetable.include?(npc.name) })
              target_result = dothistimeout "target ##{unknown_npc.id}", 10, /^You are now targeting|^You can't target|^Usage:  TARGET/
              if target_result =~ /^You are now targeting/
                @targetable.push(unknown_npc.name)
              elsif target_result =~ /^You can't target/
                @untargetable.push(unknown_npc.name)
              end
            end
            npcs = GameObj.npcs.to_a.find_all { |npc| @targetable.include?(npc.name) and not (npc.name =~ IGNORABLE) and (npc.noun !~ CLIENT_NOUN) and (($ego2_my_ambush and npc.type =~ /bandit/) or npc.status !~ DISABLED) and (npc.status !~ /dead/) }
            all_pcs = GameObj.pcs.to_a
            pcs = all_pcs.find_all { |pc| pc.status.nil? or pc.status =~ /hiding|hidden/ }
            disks = GameObj.loot.to_a.find_all { |loot| (loot.noun == 'disk') and (loot.name !~ /#{Char.name}/) and (all_pcs.empty? or (loot.name !~ /#{all_pcs.collect { |pc| pc.noun }.join('|')}/)) }
            jerks = GameObj.pcs.to_a.find_all { |pc| UserVars.attacked_me.to_a.include?(pc.noun) and (pc.status !~ /dead/) }
            unless jerks.empty?
              unless @justice_count == XMLData.room_count
                result = dothistimeout 'justice status', 1, /^There is no justice other than your own out here\.$|^You sense that your surroundings are calm enough/
                if result =~ /^There is no justice other than your own out here\.$/
                  @justice = false
                else
                  @justice = true
                end
                @justice_count = XMLData.room_count
              end
              if @justice
                jerks.clear
              end
            end
            break if @sanct_count == XMLData.room_count
            if (@poach and npcs.length > 0) or (npcs.length > 0 and ($ego2_my_ambush or (pcs.empty? and disks.empty?))) or (@attack_script and jerks.length > 0)
              if @attack_script
                if (checkrt > 0)
                  waitrt?
                  next
                elsif (checkcastrt > 0)
                  waitcastrt?
                  next
                end
                start_script(@attack_script, (jerks + npcs).collect { |n| n.id }, { :quiet=>true })
                wait_while { running?(@attack_script) }
                if clear.any? { |line| line =~ /^Be at peace my child|^Spells of War cannot be cast/ }
                  @sanct_count = XMLData.room_count
                end
              else
                puts "\n#{monsterbold_start}Kill!#{monsterbold_end} \n\n"
                pause_script
              end
            else
              break
            end
            sleep 0.1
          }
        end

        # Lay the path from here to the destination, with go2's Ta'Vaalor
        # shortcut, seeking and portals turned off, and tell how long it
        # should take.
        #
        # @return [Symbol] :found; :unmapped when the room is not in the
        #   map; :unreachable when no path leads there
        def find_path
          unless (current_room = Room.current)
            return :unmapped
          end
          # disable vaalor shortcut
          $go2_use_vaalor_shortcut = false
          Room[16745].timeto['16746'] = 15000
          Room[16746].timeto['16745'] = 15000
          # disable seeking
          $go2_use_seeking = false
          # disable portals
          $go2_use_portals = false
          Escort.close_portals
          previous, shortest_distances = Map.dijkstra(current_room.id, @destination.id)
          unless previous[@destination.id]
            return :unreachable
          end
          @path = [@destination.id]
          @path.push(previous[@path[-1]]) until previous[@path[-1]] == nil
          @path.reverse!
          est_time = ((shortest_distances[@destination.id] + (1.8 * @path.length)) / 60.0).as_time
          respond "ETA: #{est_time} (#{@path.length} rooms to move through)."
          :found
        end

        # Go one room along the path, laying the path first when this room
        # is not on it. A route of its own is taken where there is one;
        # else the map's way. A way that fails six times is taken out of
        # the map.
        #
        # @return [Symbol] :moved, or what find_path answers when it finds
        #   no path
        def step
          unless (current_room = Room.current)
            return :unmapped
          end
          unless @path && @path.include?(current_room.id)
            found = find_path
            return found unless found == :found
          end
          next_id = @path[@path.index(current_room.id) + 1].to_s
          if (miniscript = ROUTES["#{current_room.id},#{next_id}"])
            instance_exec(&miniscript)
          else
            way = current_room.wayto[next_id]
            if way.class == Proc
              way.call
            elsif way.class == String
              count = 0
              loop {
                if (move(way) == false) and not muckled?
                  unless Room.current.id == current_room.id
                    break
                  end
                  if (count += 1) > 5
                    echo 'fixing map database...'
                    echo "deleting: #{current_room.id} -> #{way} -> #{next_id} "
                    current_room.wayto.delete(next_id)
                    break
                  else
                    sleep 0.2
                  end
                else
                  break
                end
              }
            else
              @path = Array.new
            end
          end
          sleep 0.1
          :moved
        end

        # Go one room back along the path, for a client who did not follow.
        #
        # @return [Symbol] :moved; :unmapped when the room is not in the map
        def backtrack
          unless (current_room = Room.current)
            return :unmapped
          end
          begin
            next_id = @path[@path.index(current_room.id) - 1].to_s
            way = current_room.wayto[next_id]
          rescue
            echo 'error: unable to backtack'
            echo $!
            way = proc { sleep 3 }
          end
          if way.class == Proc
            way.call
          elsif way.class == String
            if (move(way) == false) and not muckled?
              echo 'fixing map database...'
              echo "deleting: #{current_room.id} -> #{way} -> #{next_id}"
              current_room.wayto.delete(next_id)
              current_room.timeto.delete(next_id)
            end
          else
            start_script 'go2', [next_id.to_s, 'typeahead=0', 'shortcut=off']
            wait_while { running?('go2') }
          end
          sleep 0.1
          :moved
        end
      end
    end
  end
end
