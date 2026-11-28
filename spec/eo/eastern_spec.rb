# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/settings'
require_relative '../../scripts/eo/brooch'
require_relative '../../scripts/eo/inventory/carry'

# Times the game prints in US Eastern, read the same on a machine in any zone.
RSpec.describe 'Eastern time' do
  # TZ strings Ruby reads on every platform (Windows has no zone names)
  zones = %w[EST5EDT PST8PDT CST6CDT UTC0].freeze

  def in_zone(zone)
    saved = ENV.fetch('TZ', nil)
    ENV['TZ'] = zone
    yield
  ensure
    saved ? ENV['TZ'] = saved : ENV.delete('TZ')
  end

  describe 'EO.parse_eastern' do
    cases = {
      'Tue Feb 10 20:30:45 2026' => Time.utc(2026, 2, 11, 1, 30, 45),   # EST, UTC-5
      'Sat Nov 30 10:53:59 2024' => Time.utc(2024, 11, 30, 15, 53, 59), # EST
      'Mon Jul  6 12:00:00 2026' => Time.utc(2026, 7, 6, 16, 0, 0),     # EDT, UTC-4
      'Sat Mar  7 23:00:00 2026' => Time.utc(2026, 3, 8, 4, 0, 0),      # EST, the night before the clocks go forward
      'Sun Mar  8 03:00:00 2026' => Time.utc(2026, 3, 8, 7, 0, 0)       # EDT, the morning after
    }.freeze

    zones.each do |zone|
      cases.each do |text, expected|
        it "reads #{text.inspect} as #{expected.iso8601} on a machine set to #{zone}" do
          expect(in_zone(zone) { EO.parse_eastern(text) }).to eq(expected)
        end
      end
    end
  end

  describe 'EO.eastern_daylight?' do
    it 'starts at 2:00 on the second Sunday of March and ends at 2:00 on the first Sunday of November' do
      expect(EO.eastern_daylight?(Time.utc(2026, 3, 8, 6, 59))).to be(false)
      expect(EO.eastern_daylight?(Time.utc(2026, 3, 8, 7, 0))).to be(true)
      expect(EO.eastern_daylight?(Time.utc(2026, 11, 1, 5, 59))).to be(true)
      expect(EO.eastern_daylight?(Time.utc(2026, 11, 1, 6, 0))).to be(false)
    end
  end

  describe 'EO::Carry.read_simu_until' do
    zones.each do |zone|
      it "ends the SimuCoin reduction at the same moment on a machine set to #{zone}" do
        line = 'Encumbrance Reduction                             Until Tue Feb 10 20:30:45 ET 2026'
        allow(EO).to receive(:command).and_return([line])
        expect(in_zone(zone) { EO::Carry.read_simu_until }).to eq(Time.utc(2026, 2, 11, 1, 30, 45))
      end
    end
  end
end
