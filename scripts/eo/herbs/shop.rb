# frozen_string_literal: true

module EO
  module Herbs
    # The herbalist: the menu, what on it treats a type, ordering and
    # buying, what a thing costs, and bundling what the sack holds.
    #
    # Commands go through the running script's helpers (EO.use). The helper
    # this needs: a lines helper, lines(text, pattern), answering the lines
    # of a command sent quietly.
    module Shop
      module_function

      # What bundling by POUR takes: a potion or the like.
      POURED = /potion|tincture|elixir|barrel|flagon|tea|soup/

      # The shop's menu, from ORDER.
      #
      # @return [Hash{String => String}] each item's name, without its
      #   article, to its number on the menu
      def menu
        lines = EO.lines('order', %r{<output class="mono"/>|<closeDialog id='dlgCustomize'/>})
        menu = {}
        lines.each do |line|
          line.scan(%r{<d.*?cmd=["']order ([0-9]+).*?>(.*?)</d>}).each do |item|
            menu[item[1].sub(/^an? /, '')] = item[0]
          end
        end
        menu
      end

      # The name on a menu of something that treats a type.
      #
      # @param menu [Hash{String => String}]
      # @param type [String] a type, or a heading of blood
      # @return [String, nil]
      def on_menu(menu, type)
        menu.keys.find { |name| Table::KNOWN.any? { |h| Table.in_category?(h, type) && (name == h[:name] || name == h[:short_name]) } }
      end

      # ORDER a number of an item, clearing both hands into the sack when
      # the shop wants a free hand.
      #
      # @param amount [Integer]
      # @param number [String] the item's number on the menu
      # @param sack [GameObj] the herb sack
      # @return [void]
      def order(amount, number, sack)
        order_result = dothistimeout "order #{amount} #{number}", 3, /^You will need a free hand|BUY/
        return unless order_result =~ /You will need a free hand/

        fput "put ##{GameObj.right_hand.id} in #{sack}"
        fput "put ##{GameObj.left_hand.id} in #{sack}"
      end

      # BUY what was ordered. A herb the table knows that is then in a hand
      # has its doses recorded.
      #
      # @return [Symbol] :sold, :no_silver, :no_hand, or :other
      def buy
        buy_result = dothistimeout 'buy', 3, /Sold for [0-9,]+ silver|^But you do not have enough silver!|You're going to need a free hand/
        case buy_result
        when /Sold for ([0-9,]+) silver/
          item = [GameObj.right_hand, GameObj.left_hand].find { |obj| Table::KNOWN.any? { |herb| herb[:name] =~ /#{obj.name}/ || herb[:short_name] =~ /#{obj.name}/ } }
          if item && (info = Table::KNOWN.find { |h| h[:name] == item.name })
            $eherbs_measure[item.id] = info[:store_doses]
          end
          :sold
        when /^But you do not have enough silver!/ then :no_silver
        when /You're going to need a free hand/ then :no_hand
        else :other
        end
      end

      # What one item on the menu costs, asked by ordering it.
      #
      # @param number [String] the item's number on the menu
      # @return [Integer, nil]
      def price(number)
        lines = EO.lines("order #{number}", /You ask/)
        lines.map { |string| string.scan(/\b([\d,]+)\s*(?:silver|silvers)\b/).flatten.first }.compact.first&.gsub(',', '')&.to_i
      end

      # The table's entry for a name on a menu, of those that are bought.
      #
      # @param name [String]
      # @return [Hash, nil]
      def entry_for(name)
        Table::KNOWN.find { |h| (h[:name] =~ /#{name}/ || h[:short_name] =~ /#{name}/) && !h[:location].include?('Do Not Buy') }
      end

      # Where herbs are bought from here: this place when any are sold in
      # it, else the nearest town.
      #
      # @return [String] a location, as the map names it
      def location
        here = Room.current.location
        Table.sold_at?(here) ? here : Room[Room.current.find_nearest_by_tag('town')].location
      end

      # The herb sold at a place for a heading, of a form when one is asked for.
      #
      # @param category [String] a type, or a heading of blood
      # @param location [String]
      # @param form [String, nil] 'drinkable', 'edible', or nil for either
      # @return [Hash, nil] the table's entry
      def sold(category, location, form = nil)
        Table::KNOWN.find do |h|
          next false unless Table.in_category?(h, category) && h[:location].any? { |place| place =~ /#{location}/ }

          case form
          when 'drinkable' then h[:name] =~ Table::DRINKABLE
          when 'edible' then h[:name] !~ Table::DRINKABLE
          else true
          end
        end
      end

      # What the sack holds for a heading, of a form when one is asked for.
      #
      # @param contents [Hash{Symbol => Array<GameObj>}] the sack's contents by form
      # @param category [String]
      # @param form [String, nil] 'drinkable', 'edible', or nil for either
      # @return [Array<GameObj>]
      def held(contents, category, form = nil)
        named = lambda do |obj, h|
          h[:name] =~ /#{obj.name}/ || h[:short_name] =~ /#{obj.name}/ || h[:short_name].include?(obj.name.sub('elixir', ''))
        end
        case form
        when 'drinkable'
          contents[:drinkable].find_all { |obj| Table::KNOWN.find { |h| named.call(obj, h) && Table.in_category?(h, category) && h[:name] =~ Table::DRINKABLE } }
        when 'edible'
          contents[:edible].find_all { |obj| Table::KNOWN.find { |h| named.call(obj, h) && Table.in_category?(h, category) && h[:name] !~ Table::DRINKABLE } }
        else
          contents[:all].find_all { |obj| Table::KNOWN.find { |h| named.call(obj, h) && Table.in_category?(h, category) } }
        end
      end

      # @param items [Array<GameObj>]
      # @return [Integer] the doses they are known to hold in all
      def doses(items)
        items.sum { |h| $eherbs_measure[h.id].to_i }
      end

      # Bundle what the sack holds: for each herb name, everything of it is
      # brought together, by BUNDLE or by POUR for what is drunk; a bundle
      # that fills up is measured and put back, and the next one started.
      #
      # @param sack [GameObj] the herb sack, its contents known
      # @param herb [String, nil] one herb name, or nil for every herb
      # @return [Symbol, nil] :enough when the game would give no more from
      #   the sack, and the bundling stopped there
      def bundle_all(sack, herb = nil)
        herbs = herb.nil? ? Table::KNOWN.map { |item| item[:name] }.uniq : [herb]

        ignore_list = []
        herbs.each do |thing|
          bundle = sack.contents.find_all { |item| item.full_name.lstrip =~ /#{thing}/ }
          next if bundle.length <= 1

          bundle = bundle[0]
          full = false

          return :enough if Sack.take(bundle) == :enough
          ignore_list.push(bundle.id)

          until (item = sack.contents.find { |h| h.full_name.lstrip =~ /#{thing}/ && !ignore_list.include?(h.id) }).nil?
            unless bundle
              bundle = item
              return :enough if Sack.take(item) == :enough
              ignore_list.push(item.id)
              next
            end

            return :enough if Sack.take(item) == :enough

            if item.name =~ POURED
              pour_result = nil
              pour_result = dothis "pour ##{item.id} in ##{bundle.id}", /You have|You only|You can|twinkling/ until pour_result =~ /You can|twinkling/
              full = true if pour_result =~ /You can/
            else
              bundle_result = dothis 'bundle', /Carefully|If you|Try as|You can't|That is not an herb you can bundle/i
              if bundle_result =~ /If you/
                full = true
              elsif bundle_result =~ /Try as|You can't|That is not an herb you can bundle/
                dothistimeout "measure ##{item.id}", 2, /^The .*? left/
                Sack.put(item.id, sack.id)
                ignore_list.push(item.id)
              else
                bundle = GameObj.right_hand
              end
            end

            if full
              dothistimeout "measure ##{bundle.id}", 2, /^The .*? left/
              Sack.put(bundle.id, sack.id)
              bundle = item
              full = false
            end

            ignore_list.push(item.id)
          end

          if bundle
            dothistimeout "measure ##{bundle.id}", 2, /^The .*? left/
            Sack.put(bundle.id, sack.id)
          end
        end
        nil
      end
    end
  end
end
