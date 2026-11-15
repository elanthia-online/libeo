# frozen_string_literal: true

module EO
  module Guild
    module Escort
      # The parts of the escort roads the map's own way does not take
      # well with a client following. One row for each "from,to" pair of
      # room ids: the kind of route, and what that kind needs. Walk#step
      # hands the row to Walk#take_route.
      #
      #   :climb way              the move, then hide
      #   :guarded way, ...       shield, clear the room and haste before
      #                           the move. :hands empties the hands for
      #                           it, :wait waits out its roundtime, :hide
      #                           hides after
      #   :sneak direction, ...   the Darkstone caves: clear the room,
      #                           haste, stand and hide, then the move,
      #                           until the room changes. The room is
      #                           cleared once more with
      #                           :check_before_stand or :check_after_stand
      #   :steps way, ...         several moves, the client caught up with
      #                           between them
      #   :ladder way, ...        several moves with the hands empty
      #   :winding path, a, b     two moves over and over while the path
      #                           is among the room's exits
      #   :cart                   a mining cart of Zul Logoth
      #   :ferry room             the ferry, from the room it is boarded in
      #   :crack                  the crack searched through from both sides
      #   :northwest_path,        ways that have to be searched for
      #   :hidden_path, :footpath
      #   :misty_trail            the trail that leads off a different
      #                           way each time
      ROUTES = {
        '2524,2523'   => [:climb, 'climb rockslide'],
        '2510,2509'   => [:climb, 'climb bank'],
        '2509,2510'   => [:climb, 'climb bank'],
        '2502,2503'   => [:climb, 'climb branch'],
        '2505,2504'   => [:climb, 'climb tree'],
        '75,74'       => [:climb, 'climb wall'],
        '74,75'       => [:climb, 'climb wall'],
        '884,883'     => [:climb, 'climb boulders'],
        '883,884'     => [:climb, 'climb boulders'],
        '991,990'     => [:guarded, 'climb trail', :hands],
        '990,991'     => [:guarded, 'climb trail', :hands],
        '990,989'     => [:guarded, 'climb path', :hands],
        '989,990'     => [:guarded, 'climb path', :hands],
        '989,988'     => [:guarded, 'climb mountainside', :hands],
        '988,989'     => [:guarded, 'climb mountainside', :hands],
        '971,970'     => [:guarded, 'go fissure', :wait, :hide],
        '970,971'     => [:guarded, 'go fissure', :wait, :hide],
        '964,963'     => [:climb, 'climb boulders'],
        '963,964'     => [:climb, 'climb boulders'],
        '902,901'     => [:guarded, 'go crevasse', :hide],
        '1018,1017'   => [:climb, 'climb precipice'],
        '1017,1018'   => [:climb, 'climb cliff'],
        '1024,1025'   => [:guarded, 'climb ledge', :wait],
        '1025,1024'   => [:guarded, 'climb cliff', :wait],
        '1156,1155'   => [:guarded, 'north', :wait],
        '1153,1154'   => [:guarded, 'south', :wait],
        '1236,1237'   => [:guarded, 'go stream'],
        '1239,1238'   => [:guarded, 'go stream'],
        '1224,1223'   => [:guarded, 'climb boulder', :hands],
        '1223,1224'   => [:guarded, 'climb boulder', :hands],
        '1219,1220'   => [:northwest_path],
        '1030,1029'   => [:climb, 'climb cliff'],
        '1029,1030'   => [:climb, 'climb cliff'],
        '1020,1019'   => [:climb, 'climb crevice'],
        '1019,1020'   => [:climb, 'climb crevice'],
        '1242,1241'   => [:hidden_path],
        '10117,10119' => [:ferry, 10117],
        '10119,10117' => [:ferry, 10119],
        '1216,1217'   => [:footpath],
        '2547,2546'   => [:sneak, 'northeast', :check_before_stand],
        '2547,2548'   => [:sneak, 'southwest', :check_before_stand],
        '2545,2544'   => [:sneak, 'north', :check_after_stand],
        '2545,2546'   => [:sneak, 'southwest'],
        '2536,2535'   => [:sneak, 'east'],
        '2536,2537'   => [:sneak, 'west'],
        '2535,2534'   => [:sneak, 'southeast'],
        '2535,2536'   => [:sneak, 'west'],
        '2534,2533'   => [:sneak, 'southeast'],
        '2534,2535'   => [:sneak, 'northwest'],
        '2526,2525'   => [:sneak, 'east'],
        '2526,2527'   => [:sneak, 'west'],
        '2525,2524'   => [:sneak, 'northeast'],
        '2525,2526'   => [:sneak, 'west'],
        '2524,2525'   => [:sneak, 'southwest'],
        '2522,2521'   => [:sneak, 'northeast'],
        '2522,2523'   => [:sneak, 'west'],
        '2521,2520'   => [:sneak, 'northeast'],
        '2521,2522'   => [:sneak, 'southwest'],
        '2518,2519'   => [:sneak, 'west'],
        '2518,2517'   => [:sneak, 'northeast'],
        '2516,2515'   => [:sneak, 'north'],
        '2516,2517'   => [:sneak, 'south'],
        '2513,2512'   => [:sneak, 'northwest'],
        '2513,2514'   => [:sneak, 'south'],
        '2507,2508'   => [:sneak, 'southwest'],
        '2506,2505'   => [:sneak, 'north'],
        '2502,2501'   => [:sneak, 'north'],
        '2500,2499'   => [:sneak, 'northeast'],
        '2500,2501'   => [:sneak, 'south'],
        '2497,2498'   => [:sneak, 'southwest'],
        '2497,2496'   => [:sneak, 'west'],
        '1012,1013'   => [:cart],
        '1260,1261'   => [:cart],
        '1266,1267'   => [:cart],
        '992,993'     => [:cart],
        '1230,1231'   => [:crack],
        '1232,1231'   => [:crack],
        '784,786'     => [:steps, 'south', 'south', 'west'],
        '786,784'     => [:steps, 'east', 'east', 'north', 'east', 'north'],
        '1042,1041'   => [:misty_trail],
        '1808,1811'   => [:steps, 'southwest', 'southwest', 'southwest', 'northwest', 'northwest'],
        '1811,1808'   => [:steps, 'southeast', 'southeast', 'northeast', 'northeast', 'northeast'],
        '1074,1075'   => [:climb, 'southeast'],
        '1074,1073'   => [:ladder, 'climb ladder', 'climb down', 'climb down', 'climb down'],
        '1070,1071'   => [:ladder, 'climb ladder', 'climb up', 'climb up', 'climb up'],
        '785,786'     => [:winding, 's', 'south', 'west'],
        '785,784'     => [:winding, 'n', 'east', 'north']
      }.freeze

      # Taking the routes of ROUTES.
      class Walk
        # Take one route.
        #
        # @param kind [Symbol] the first cell of a row of ROUTES
        # @param args [Array] the rest of the row
        # @return [void]
        def take_route(kind, *args)
          send(:"route_#{kind}", *args)
        end

        private

        # Give the client time to arrive: up to two seconds, then one more.
        def escort_catch_up
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
        end

        def route_climb(way)
          move way
          hide
        end

        def route_guarded(way, *also)
          protect
          check_room
          haste
          empty_hands if also.include?(:hands)
          move way
          waitrt? if also.include?(:hands) || also.include?(:wait)
          fill_hands if also.include?(:hands)
          hide if also.include?(:hide)
        end

        def route_sneak(direction, check = nil)
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            check_room if check == :check_before_stand
            fput 'stand' unless standing?
            check_room if check == :check_after_stand
            hide
            dothistimeout direction, 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        end

        def route_steps(*ways)
          ways.each_with_index do |way, i|
            escort_catch_up unless i.zero?
            haste
            hide
            move way
          end
        end

        def route_ladder(*ways)
          empty_hands
          haste
          ways.each do |way|
            move way
            waitrt?
          end
          fill_hands
        end

        def route_winding(path, first, second)
          while checkpaths.include?(path)
            move first
            escort_catch_up
            haste
            hide
            move second
            escort_catch_up
            haste
            hide
          end
        end

        # Buy a ticket, wait up to thirty seconds to be put aboard and up
        # to six minutes to be put off, then for the client.
        def route_cart
          dothistimeout 'buy ticket', 10, /^You already bought a ticket.$|^The dwarf .*You now have passage/
          bug = true
          300.times {
            sleep 0.1
            if clear.any? { |line| line =~ /^You hastily enter the mining cart./ }
              bug = false
              break
            end
          }
          unless bug
            3600.times {
              sleep 0.1
              break if clear.any? { |line| line =~ /^You hastily exit the cart/ }
              check_room
            }
          end
          100.times {
            check_room
            sleep 0.2
            break if escort_here?
          }
        end

        # Board, waiting for the ferry when it is not in; cross; and leave.
        def route_ferry(boarding_room)
          move 'go gangplank'
          if Room.current.id == boarding_room
            echo 'Waiting for ferry... '
            loop {
              break if clear.include?('An elven crewmember scrambles back onto the boat and lowers the gangplank.')
              check_room
              sleep 0.1
            }
            move 'go gangplank'
          end
          loop {
            break if clear.include?('An elven crewmember scrambles back onto the boat and lowers the gangplank.')
            check_room
            sleep 0.1
          }
          haste
          check_room
          hide
          check_room
          hide
          check_room
          move 'out'
        end

        def route_crack
          haste
          dothistimeout 'search', 5, /You search/
          waitrt?
          check_room
          haste
          check_room
          hide
          move 'go crack'
          haste
          dothistimeout 'search', 5, /You search/
          waitrt?
          15.times { sleep 0.1; break if escort_here? }
          haste
          hide
          move 'go opening'
        end

        def route_northwest_path
          haste
          3.times {
            result = dothistimeout 'search', 3, /^don't find anything|discover a northwest path|Round\s?time/
            waitrt?
            check_room
            break if result =~ /discover a northwest path/
          }
          haste
          hide
          check_room
          hide
          check_room
          move 'go path'
        end

        def route_hidden_path
          haste
          5.times {
            search_result = dothistimeout 'search', 5, /discover a|don't find anything|Round\s?time/
            waitrt?
            check_room
            break if search_result =~ /discover a/
          }
          check_room
          haste
          check_room
          hide
          check_room
          hide
          check_room
          move 'go path'
        end

        def route_footpath
          5.times {
            search_result = dothistimeout 'search', 5, /don't find anything|discover a small footpath|^Round\s?time/
            fput 'search'
            waitrt?
            check_room
            break if search_result =~ /discover a small footpath/
          }
          check_room
          haste
          check_room
          hide
          check_room
          hide
          check_room
          move 'go footpath'
        end

        def route_misty_trail
          move 'climb boulder'
          check_room
          hide
          escort_catch_up
          look_result = dothistimeout 'look trail', 5, /^You peer into the mist and see that the trail heads off to the/
          dir = /^You peer into the mist and see that the trail heads off to the (\w+)/.match(look_result).captures.first
          haste
          hide
          move 'down'
          escort_catch_up
          haste
          hide
          move dir
        end
      end
    end
  end
end
