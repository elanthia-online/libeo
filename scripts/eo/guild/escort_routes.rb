# frozen_string_literal: true

module EO
  module Guild
    module Escort
      # The parts of the escort roads the map's own way does not take
      # well with a client following: climbs that end hiding, moves to
      # keep the room clear before, the sneaking in the Darkstone caves,
      # hidden paths to search for, the mining carts and the ferry, and
      # roads where the client must catch up between moves. One entry
      # for each "from,to" pair of room ids; Walk#step runs it as a part
      # of the walk.
      ROUTES = {
        '2524,2523'   => proc {
          move 'climb rockslide'
          hide
        },
        '2510,2509'   => proc {
          move 'climb bank'
          hide
        },
        '2509,2510'   => proc {
          move 'climb bank'
          hide
        },
        '2502,2503'   => proc {
          move 'climb branch'
          hide
        },
        '2505,2504'   => proc {
          move 'climb tree'
          hide
        },
        '75,74'       => proc {
          move 'climb wall'
          hide
        },
        '74,75'       => proc {
          move 'climb wall'
          hide
        },
        '884,883'     => proc {
          move 'climb boulders'
          hide
        },
        '883,884'     => proc {
          move 'climb boulders'
          hide
        },
        '991,990'     => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb trail'
          waitrt?
          fill_hands
        },
        '990,991'     => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb trail'
          waitrt?
          fill_hands
        },
        '990,989'     => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb path'
          waitrt?
          fill_hands
        },
        '989,990'     => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb path'
          waitrt?
          fill_hands
        },
        '989,988'     => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb mountainside'
          waitrt?
          fill_hands
        },
        '988,989'     => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb mountainside'
          waitrt?
          fill_hands
        },
        '971,970'     => proc {
          protect
          check_room
          haste
          move 'go fissure'
          waitrt?
          hide
        },
        '970,971'     => proc {
          protect
          check_room
          haste
          move 'go fissure'
          waitrt?
          hide
        },
        '964,963'     => proc {
          move 'climb boulders'
          hide
        },
        '963,964'     => proc {
          move 'climb boulders'
          hide
        },
        '902,901'     => proc {
          protect
          check_room
          haste
          move 'go crevasse'
          hide
        },
        '1018,1017'   => proc {
          move 'climb precipice'
          hide
        },
        '1017,1018'   => proc {
          move 'climb cliff'
          hide
        },
        '1024,1025'   => proc {
          protect
          check_room
          haste
          move 'climb ledge'
          waitrt?
        },
        '1025,1024'   => proc {
          protect
          check_room
          haste
          move 'climb cliff'
          waitrt?
        },
        '1156,1155'   => proc {
          protect
          check_room
          haste
          move 'north'
          waitrt?
        },
        '1153,1154'   => proc {
          protect
          check_room
          haste
          move 'south'
          waitrt?
        },
        '1236,1237'   => proc {
          protect
          check_room
          haste
          move 'go stream'
        },
        '1239,1238'   => proc {
          protect
          check_room
          haste
          move 'go stream'
        },
        '1224,1223'   => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb boulder'
          waitrt?
          fill_hands
        },
        '1223,1224'   => proc {
          protect
          check_room
          haste
          empty_hands
          move 'climb boulder'
          waitrt?
          fill_hands
        },
        '1219,1220'   => proc {
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
        },
        '1030,1029'   => proc {
          move 'climb cliff'
          hide
        },
        '1029,1030'   => proc {
          move 'climb cliff'
          hide
        },
        '1020,1019'   => proc {
          move 'climb crevice'
          hide
        },
        '1019,1020'   => proc {
          move 'climb crevice'
          hide
        },
        '1242,1241'   => proc {
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
        },
        '10117,10119' => proc {
          move 'go gangplank'
          if Room.current.id == 10117
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
        },
        '10119,10117' => proc {
          move 'go gangplank'
          if Room.current.id == 10119
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
        },
        '1216,1217'   => proc {
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
        },
        '2547,2546'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            check_room
            fput 'stand' unless standing?
            hide
            dothistimeout 'northeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2547,2548'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            check_room
            fput 'stand' unless standing?
            hide
            dothistimeout 'southwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2545,2544'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            check_room
            hide
            dothistimeout 'north', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2545,2546'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'southwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2536,2535'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'east', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2536,2537'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'west', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2535,2534'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'southeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2535,2536'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'west', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2534,2533'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'southeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2534,2535'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'northwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2526,2525'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'east', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2526,2527'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'west', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2525,2524'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'northeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2525,2526'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'west', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2524,2525'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'southwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2522,2521'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'northeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2522,2523'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'west', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2521,2520'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'northeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2521,2522'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'southwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2518,2519'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'west', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2518,2517'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'northeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2516,2515'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'north', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2516,2517'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'south', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2513,2512'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'northwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2513,2514'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'south', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2507,2508'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'southwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2506,2505'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'north', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2502,2501'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'north', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2500,2499'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'northeast', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2500,2501'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'south', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2497,2498'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'southwest', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '2497,2496'   => proc {
          room_count = XMLData.room_count
          while room_count == XMLData.room_count
            check_room
            haste
            fput 'stand' unless standing?
            hide
            dothistimeout 'west', 3, /^Trying to sneak over|^Obvious|^Running heedlessly/
          end
        },
        '1012,1013'   => proc {
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
        },
        '1260,1261'   => proc {
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
        },
        '1266,1267'   => proc {
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
        },
        '992,993'     => proc {
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
        },
        '1230,1231'   => proc {
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
        },
        '1232,1231'   => proc {
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
        },
        '784,786'     => proc {
          haste
          hide
          move 'south'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'south'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'west'
        },
        '786,784'     => proc {
          haste
          hide
          move 'east'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'east'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'north'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'east'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'north'
        },
        '1042,1041'   => proc {
          move 'climb boulder'
          check_room
          hide
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          look_result = dothistimeout 'look trail', 5, /^You peer into the mist and see that the trail heads off to the/
          dir = /^You peer into the mist and see that the trail heads off to the (\w+)/.match(look_result).captures.first
          haste
          hide
          move 'down'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move dir
        },
        '1808,1811'   => proc {
          haste
          hide
          move 'southwest'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'southwest'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'southwest'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'northwest'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'northwest'
        },
        '1811,1808'   => proc {
          haste
          hide
          move 'southeast'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'southeast'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'northeast'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'northeast'
          10.times { check_room; sleep 0.2; break if escort_here? }
          10.times { check_room; sleep 0.1 }
          haste
          hide
          move 'northeast'
        },
        '1074,1075'   => proc {
          move 'southeast'
          hide
        },
        '1074,1073'   => proc {
          empty_hands
          haste
          move 'climb ladder'
          waitrt?
          move 'climb down'
          waitrt?
          move 'climb down'
          waitrt?
          move 'climb down'
          waitrt?
          fill_hands
        },
        '1070,1071'   => proc {
          empty_hands
          haste
          move 'climb ladder'
          waitrt?
          move 'climb up'
          waitrt?
          move 'climb up'
          waitrt?
          move 'climb up'
          waitrt?
          fill_hands
        },
        '785,786'     => proc {
          while checkpaths.include?('s')
            move 'south'
            10.times { check_room; sleep 0.2; break if escort_here? }
            10.times { check_room; sleep 0.1 }
            haste
            hide
            move 'west'
            10.times { check_room; sleep 0.2; break if escort_here? }
            10.times { check_room; sleep 0.1 }
            haste
            hide
          end
        },
        '785,784'     => proc {
          while checkpaths.include?('n')
            move 'east'
            10.times { check_room; sleep 0.2; break if escort_here? }
            10.times { check_room; sleep 0.1 }
            haste
            hide
            move 'north'
            10.times { check_room; sleep 0.2; break if escort_here? }
            10.times { check_room; sleep 0.1 }
            haste
            hide
          end
        },
      }.freeze
    end
  end
end
