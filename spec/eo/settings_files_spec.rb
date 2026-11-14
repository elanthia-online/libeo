# frozen_string_literal: true

require 'tmpdir'
require_relative 'eo_helper'
require_relative '../../scripts/eo/settings'

RSpec.describe EO::Settings, 'profile files' do
  around do |example|
    Dir.mktmpdir { |dir| (@dir = dir) && example.run }
  end

  before do
    stub_const('DATA_DIR', @dir)
    stub_const('XMLData', Struct.new(:game).new('GSIV'))
    stub_const('Char', Struct.new(:name).new('Nisugi'))
    messaging = Module.new
    messaging.define_singleton_method(:msg) { |_kind, text| (@said ||= []) << text }
    messaging.define_singleton_method(:said) { @said ||= [] }
    stub_const('Lich::Messaging', messaging)
  end

  let(:path) { described_class.profile_path('eloot') }
  let(:said) { Lich::Messaging.said }

  def write(text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  describe '.save_profile' do
    it 'leaves no temporary file and replaces a file already there' do
      described_class.save_profile('eloot', { tip: 5 })
      described_class.save_profile('eloot', { tip: 6 })
      expect(described_class.load_profile('eloot')).to eq(tip: 6)
      expect(Dir.children(File.dirname(path))).to eq(['eloot.yaml'])
    end

    it 'writes through a temporary file, so a failed write leaves the old file whole' do
      described_class.save_profile('eloot', { tip: 5 })
      allow(File).to receive(:write).and_raise(Errno::ENOSPC)
      expect { described_class.save_profile('eloot', { tip: 6 }) }.to raise_error(Errno::ENOSPC)
      allow(File).to receive(:write).and_call_original
      expect(described_class.load_profile('eloot')).to eq(tip: 5)
    end

    it 'tries the rename again when Windows has the file open, then gives up' do
      described_class.save_profile('eloot', { tip: 5 })
      calls = 0
      allow(File).to receive(:rename).and_wrap_original do |original, *args|
        calls += 1
        raise Errno::EACCES if calls < 3

        original.call(*args)
      end
      allow(described_class).to receive(:sleep)
      described_class.save_profile('eloot', { tip: 6 })
      expect(calls).to eq(3)
      expect(described_class.load_profile('eloot')).to eq(tip: 6)

      allow(File).to receive(:rename).and_raise(Errno::EACCES)
      expect { described_class.save_profile('eloot', { tip: 7 }) }.to raise_error(Errno::EACCES)
      expect(Dir.children(File.dirname(path))).to eq(['eloot.yaml'])
    end

    it 'saves dates, times, ranges and sets so they load back' do
      values = { day: Date.new(2026, 11, 14), at: Time.at(1_700_000_000).utc, span: 1..3, set: Set[1, 2] }
      described_class.save_profile('eloot', values)
      expect(described_class.load_profile('eloot')).to eq(values)
    end
  end

  describe '.load_profile' do
    it 'moves a file it cannot read aside, names it, and reads as no profile' do
      write(":skin: \"tr\n")
      expect(described_class.load_profile('eloot')).to be_nil
      expect(File.exist?(path)).to be(false)
      expect(File.exist?("#{path}.bad")).to be(true)
      expect(said.first).to include(path).and include('.bad')
    end

    it 'does the same with a file that is not a hash of settings' do
      write("just some words\n")
      expect(described_class.load_profile('eloot')).to be_nil
      expect(File.exist?("#{path}.bad")).to be(true)
    end

    it 'reads an empty file as no profile and leaves it' do
      write('')
      expect(described_class.load_profile('eloot')).to be_nil
      expect(File.exist?(path)).to be(true)
    end

    it 'lets a script start on a bad file' do
      write("\t:::\n")
      expect(described_class::Store.new('eloot').to_h).to eq({})
    end
  end

  describe '.preload' do
    it 'goes on to the other scripts after one that cannot be read' do
      described_class.save_profile('echild', { a: 1 })
      FileUtils.mkdir_p(File.dirname(path))
      File.write(described_class.profile_path('ebounty'), ":b: \"x\n")
      allow(described_class).to receive(:load_profile).and_call_original
      described_class.preload(%w[ebounty echild])
      expect(described_class.read(:echild)).to eq(a: 1)
      expect(File.exist?("#{described_class.profile_path('ebounty')}.bad")).to be(true)
    end

    it 'says which script it could not read when something else goes wrong' do
      allow(described_class).to receive(:load_profile).with('ebounty').and_raise(IOError, 'disk')
      allow(described_class).to receive(:load_profile).with('echild')
      described_class.preload(%w[ebounty echild])
      expect(said.first).to include('ebounty').and include('disk')
      expect(described_class).to have_received(:load_profile).with('echild')
    end
  end
end
