# frozen_string_literal: true

module EO
  module Loot
    # The standard hooks a looting pass needs, the way eloot has them, and what
    # the character carries for it. eloot still passes its own; these are for a
    # script that is not eloot (EO::Loot.build), and a spec holds them to
    # eloot's so the two do not drift apart.
    module Hooks
      module_function

      # A roundtime answer get_command sends the command again after. It also
      # matches "Roundtime: N sec.", which a command that ran leaves (EO.command
      # does not send again on it); kept as eloot has it, to change in both at once.
      COMMAND_RT = /(?:Roundtime:|\.\.\.wait) (\d+) [Ss]ec(?:onds)?\./i
      # get_res's: it also takes "Wait N sec" and the rash.
      RESULT_RT = /(?:Roundtime:|\.\.\.wait|Wait) (\d+) [Ss]ec(?:onds?)?\.?|An uncontrollable urge to scratch the rash/

      # @param context [EO::Loot::Context]
      # @return [Proc] eloot's get_command
      def command(context)
        lambda do |command, regex, silent: nil, quiet: false, timeout: 5|
          if context.settings[:debug]
            silent = nil
            quiet = false
          end
          lines = []
          regex = Regexp.union(regex, COMMAND_RT)
          begin
            lines = Lich::Util.issue_command(command, regex, usexml: true, silent: silent, quiet: quiet, timeout: timeout)
            context.say(type: 'debug', text: "command: #{command} | lines - #{lines}")
            raise if lines.any? { |l| l =~ COMMAND_RT }
          rescue StandardError
            EO.settle
            retry
          end
          lines
        end
      end

      # @return [Proc] eloot's get_res
      def result(context)
        lambda do |command, regex = nil|
          context.say(type: 'debug', text: "command: #{command}")
          regex = regex.nil? ? Regexp.union(/.*?/, RESULT_RT) : Regexp.union(regex, RESULT_RT)
          answer = nil
          loop do
            answer = dothistimeout(command, 3, regex)
            break unless answer =~ RESULT_RT

            EO.settle
          end
          answer
        end
      end

      # @return [Proc] eloot's wait_for_disk
      def wait_for_disk(context)
        lambda do
          next unless context.settings[:use_disk]
          next unless context.disk

          context.say(type: 'info', text: ' Waiting for your disk to arrive') if context.disk.status&.include?('gone') || Items::Disk.mine.nil?
          context.disk = Items::Disk.wait
        end
      end

      # @param hands [EO::Loot::Handler] opens the sell containers
      # @return [Proc] eloot's Sell.check_inventory: what the sell containers
      #   and the disk hold, past what is set aside not to sell
      def inventory(context, hands)
        waiting = wait_for_disk(context)
        lambda do
          all = []
          StowList.stow_list.each do |item, container|
            next unless container
            next unless context.settings[:sell_container].to_a.any? { |sell| item.to_s.match?(/#{Regexp.escape(sell)}/) }

            hands.open_single_container(container)
            all += container.contents.to_a
          end
          if context.settings[:use_disk]
            waiting.call
            all += Containers.fresh_contents(context.disk).to_a
          end
          all.reject { |thing| Array($sell_ignore).include?(thing.id) }
        end
      end

      # @return [Proc] eloot's decurse
      def decurse(context)
        lambda do |obj|
          next true unless obj.type =~ /cursed/
          next false unless context.settings[:loot_types].to_a.include?('cursed')

          case Items.decurse(obj, gauntlet: context.gauntlet)
          when :clean, :cast, :gauntlet then true
          when :no_mana
            context.say(type: 'info', text: "** #{obj.name} is cursed and you don't have enough mana to cast 315.")
            false
          else false
          end
        end
      end

      # @return [Proc] eloot's toss
      def toss(context)
        lambda do |obj, toss_cmd, attempts: 1, poll: false, notify_on_keep: false|
          case Items.toss(obj, toss_cmd, attempts: attempts, poll: poll)
          when :tossed then true
          when :marked
            context.say(type: 'info', text: " #{obj.name} is marked as unsellable, keeping it.")
            false
          else
            context.say(type: 'info', text: " #{obj.name} isn't trashed so maybe its special...keeping it.") if notify_on_keep
            false
          end
        end
      end

      # @return [Proc] eloot's unlootable
      def unlootable(context)
        lambda do |item|
          context.say(type: 'debug', text: "item: #{item}")
          next unless context.settings[:log_unlootables]
          next unless item.type.nil?

          context.say(type: 'info', text: " #{item.name} was not lootable, adding to list.")
          (context.settings[:unlootable] ||= []).push(item.name)
          context.save
        end
      end

      # @return [Proc] eloot's change_stance
      def stance(context)
        lambda do |stance|
          context.say(type: 'debug', text: "stance: #{stance}")
          next unless Stance::NAMES.include?(stance) # 'none' or unset
          next if Effects::Debuffs.active?('Frenzy')

          Stance.change(stance)
        end
      end

      # --- what the character carries -----------------------------------------

      # Find what a pass uses that the character carries, the way eloot does at
      # its start: the fossil charm, the eonake gauntlet, the blood band (with
      # its bracer), the weapons for skinning, the disks.
      #
      # @param context [EO::Loot::Context]
      # @param issue [Proc] sends a command, as #command
      # @return [void]
      def equip(context, issue: nil)
        command = issue || command(context)
        settings = context.settings
        unless (charm_name = settings[:charm_name].to_s).empty?
          context.charm = GameObj.inv.find { |i| i.name =~ /\b#{charm_name}\b/i }
        end
        context.gauntlet = GameObj.inv.find { |i| i.name =~ /\beonake gauntlet\b/i }
        find_blood_band(context, command)
        context.weapon_inv = weapons(command)
        context.disk = Items::Disk.mine if settings[:use_disk]
        context.disk_full = Group.disks.to_h { |disk| [disk.name, false] }
      end

      # eloot's find_bloodtooth: band and bracer both, else the setting goes off.
      def find_blood_band(context, command)
        return unless context.settings[:use_bloodbands]

        bracer = false
        GameObj.inv.each do |item|
          next unless item.name =~ /bands|bracer/

          lines = command.call("analyze ##{item.id}", /You analyze/, silent: true, quiet: true)
          next unless lines.any? { |l| l =~ /magically drains some of your blood/ }

          bracer = true if item.name =~ /bracer/
          context.blood_band = item if item.name =~ /bands/
          break if bracer && context.blood_band
        end
        context.settings[:use_bloodbands] = (bracer && context.blood_band.is_a?(GameObj))
      end

      # eloot's get_weapon_inv: the weapons worn, and what is in the hands.
      #
      # @return [Array<GameObj>]
      def weapons(command)
        exist = %r{<a exist=(?:'|")(?<id>.*?)(?:'|") noun=(?:'|")(?<noun>.*?)(?:'|")>(?<name>.*?)</a>}
        found = []
        lines = command.call('inventory full weapons', /You are currently wearing:|You are carrying no weapons at this time\./, silent: true, quiet: true)
        lines.each do |line|
          line.scan(exist) do |id, noun, name|
            found << GameObj.new(id, noun, name) unless found.any? { |weapon| weapon.id =~ /#{id}/ }
          end
        end
        found << GameObj.right_hand if checkright
        found << GameObj.left_hand if checkleft
        found
      end
    end

    # A looting pass ready to run, for a script that has eloot's settings and
    # nothing of eloot's own: the standard hooks, what the character carries,
    # the hands, the floor and the skinning.
    #
    # @param settings [Hash] eloot's settings (EO::Settings.load_profile('eloot'))
    # @param say [Proc] given type: and text:, shows a message
    # @param save [Proc, nil] writes the settings back
    # @param corpses [Proc] returns the dead to skin and search
    # @param floor_loot [Boolean]
    # @return [EO::Loot::Pass]
    def self.build(settings, say:, save: nil, corpses: -> { GameObj.dead.to_a }, floor_loot: true)
      unlootable = nil
      context = Context.from_settings(settings, say: say, save: save, unlootable: ->(obj) { unlootable.call(obj) })
      unlootable = Hooks.unlootable(context)
      command = Hooks.command(context)
      Hooks.equip(context, issue: command)
      handler = nil
      inventory = -> { Hooks.inventory(context, handler).call }
      handler = Handler.new(context, command: command, inventory: inventory, wait_for_disk: Hooks.wait_for_disk(context))
      floor = Floor.new(context, hands: handler, command: command, result: Hooks.result(context), decurse: Hooks.decurse(context),
                                 unlootable: unlootable, toss: Hooks.toss(context))
      skin = (-> { Skinning::Pass.new(context, corpses: corpses.call, hands: handler, ensure_items: ->(**) {}) } if settings[:skin_enable])
      Pass.new(context, floor: floor, hands: handler, corpses: corpses, skin: skin, floor_loot: floor_loot,
                        stance: Hooks.stance(context), coin_hand: -> {}, return_hands: -> { handler.return_hands })
    end
  end
end
