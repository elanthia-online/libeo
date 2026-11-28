# frozen_string_literal: true

module EO
  # Raised by EO.room_id for a uid the map database does not know.
  class UnknownRoom < StandardError; end

  # Seconds to wait for another script's go2 to finish before walking.
  GO2_WAIT = 30
  GO2_TRIES = 3

  # The go2 wrapper every e-script re-implements: unhide, skip when already
  # there, warn on an unknown room, run go2 with --disable-confirm. Another
  # script's go2 (a hunter regrouping, say) is waited out first, since Lich
  # refuses a second one, and the walk is tried again until it arrives.
  #
  # @param place [Integer, String] room id, "u" uid, or a map tag such as 'bank'
  # @param force [Boolean] walk at once though a go2 is already running: for a
  #   caller that has paused it (ecleanse), where waiting would never end
  # @param unhide [Boolean, Symbol] true to UNHIDE first whether or not there is
  #   a walk to make (ebounty, eherbs); :walking only when about to walk
  #   (ecleanse, which may be hidden in the very room it was sent to); false never
  # @return [Boolean] whether the current room now matches +place+
  def self.go2(place, force: false, unhide: true)
    fput('unhide') if unhide == true && (hidden? || invisible?)
    return true if at?(place)

    fput('unhide') if unhide == :walking && (hidden? || invisible?)
    if Room.current.nil? || Room.current.id.nil?
      Lich::Messaging.msg('warn', "go2: in an unmapped room, heading for #{place}")
    end
    GO2_TRIES.times do
      unless force
        deadline = Time.now + GO2_WAIT
        sleep 0.2 while Script.running?('go2') && Time.now < deadline
      end
      Script.run('go2', "#{place} --disable-confirm", { quiet: true, force: force })
      return true if at?(place)
    end
    false
  end

  # @param place [Integer, String] room id, "u" uid, or a map tag
  # @return [Boolean] whether the current room is that place
  def self.at?(place)
    room = Room.current
    return false if room.nil?
    case place
    when Integer then room.id == place
    when /\A\d+\z/ then room.id == place.to_i
    when /\Au-?\d+\z/i then room.uid.to_a.map(&:to_s).include?(place[1..])
    else room.tags.include?(place.to_s)
    end
  end

  # @param tag [String]
  # @return [Integer, nil] the nearest room id carrying +tag+, avoiding FWI rooms
  #   unless the character is already on the island
  def self.nearest(tag)
    room = Room.current
    return nil if room.nil?
    candidates = room.find_all_nearest_by_tag(tag)
    candidates = candidates.reject { |id| fwi?(Room[id]) } unless fwi?(room)
    candidates.first
  end

  # @param room [Room, nil]
  # @return [Boolean] whether a room is on Four Winds Isle (Mist Harbor)
  def self.fwi?(room)
    return false if room.nil?
    room.location.to_s =~ /Mist Harbor|Four Winds/i ? true : false
  end

  # Whether to fog home after a hunt, by bigshot's fog_return rule: method
  # 0 is off, and fog_optional fogs only a rest forced by wounds or
  # encumbrance. Lich's Fog.return does the fog itself.
  #
  # @param method [Integer, String] the profile's fog_return
  # @param optional [Boolean] the profile's fog_optional
  # @param reason [String, Symbol, nil] why the hunt is resting
  # @return [Boolean]
  def self.fog_wanted?(method, optional: false, reason: nil)
    return false if method.to_i.zero?
    return false if optional && reason.to_s !~ /wounded|encumbered/
    true
  end

  # Go somewhere, do something, come back.
  #
  #   EO.visit('bank') { Lich::Gemstone::Bank.deposit }
  #
  # @param place [Integer, String] a room id or a map tag; a tag resolves to the
  #   nearest room carrying it, avoiding Four Winds Isle unless already there
  # @return [Object, nil] the block's value, nil when the place could not be reached
  def self.visit(place)
    here = Room.current&.id
    target = place.is_a?(String) && place !~ /\A[u\d]/i ? nearest(place) : place
    return nil if target.nil? || !go2(target)
    yield
  ensure
    go2(here) if here && Room.current&.id != here
  end

  # One step to a neighbouring room not yet visited, else the least
  # recently visited one, never across +avoid+.
  #
  # @param visited [Array<String>] room ids, most recent last; updated
  # @param avoid [Array<String>] room ids not to step into
  # @return [Boolean] whether a step was taken
  def self.wander(visited, avoid: [])
    room = Room.current
    return false if room.nil?
    options = room.wayto.keys - avoid
    # a map's scripted edge is a StringProc, which is not a Proc to is_a?
    options.delete_if { |id| room.timeto[id].respond_to?(:call) && room.timeto[id].call.nil? }
    fresh = options.reject { |r| visited.include?(r) }
    next_room = fresh.empty? ? visited.find { |r| options.include?(r) } : fresh.sample
    return false if next_room.nil?
    visited.delete(next_room)
    visited.push(next_room)
    way = room.wayto[next_room]
    way.is_a?(String) ? move(way) : way.call
    true
  end

  # A room id from either form settings and profiles use: a map id ("1234",
  # 1234) or a uid ("u7120").
  #
  # @param room [Integer, String]
  # @return [Integer] the map room id
  # @raise [UnknownRoom] for a uid the map database does not know
  def self.room_id(room)
    if (m = /\Au(?<uid>\d+)\z/i.match(room.to_s.strip))
      ids = Map.ids_from_uid(m[:uid].to_i)
      raise UnknownRoom, "#{room} is not in the map database" if ids.empty?
      return ids.first.to_i
    end
    room.to_i
  end
end
