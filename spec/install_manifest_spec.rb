# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative 'spec_helper'
require_relative '../lib/libeo/install'

RSpec.describe LibEO::Install, 'with a manifest that cannot be read' do
  around do |example|
    Dir.mktmpdir('libeo-manifest') do |dir|
      @directory = dir
      example.run
    end
  end

  let(:lich_dir) do
    dir = File.join(@directory, 'Lich5')
    FileUtils.mkdir_p(File.join(dir, 'scripts'))
    FileUtils.mkdir_p(File.join(dir, 'lib'))
    File.write(File.join(dir, 'lich.rbw'), '')
    File.write(File.join(dir, 'lib', 'version.rb'), "LICH_VERSION = '5.22.0'\n")
    dir
  end
  let(:manifest_path) { File.join(lich_dir, 'scripts', described_class::MANIFEST) }

  def payload(version: '1.0.0', parts: %w[help.rb travel.rb])
    root = File.join(@directory, "payload-#{version}")
    FileUtils.mkdir_p(File.join(root, 'eo'))
    File.write(File.join(root, 'libeo.lic'), "=begin\n      required: Lich >= 5.22.0\n=end\n")
    File.write(File.join(root, 'eo', 'version.rb'), "  VERSION = '#{version}'.freeze\n")
    parts.each { |part| File.write(File.join(root, 'eo', part), "# #{part}\n") }
    root
  end

  def break_manifest(text)
    FileUtils.mkdir_p(File.dirname(manifest_path))
    File.write(manifest_path, text)
  end

  [['cut short', '{"version": "1.0'], ['empty', ''], ['no files', '{"version":"1"}'], ['files not a hash', '{"files":[]}']].each do |name, text|
    it "names the file instead of failing in the parser when the manifest is #{name}" do
      break_manifest(text)
      expect { described_class.manifest(lich_dir) }.to raise_error(described_class::Error, /#{Regexp.escape(manifest_path)}/)
      expect { described_class.uninstall(lich_dir) }.to raise_error(described_class::Error, /libeo install/)
      expect { described_class.check(lich_dir) }.to raise_error(described_class::Error, /libeo install/)
    end
  end

  it 'installs over it, saying so, and writes a manifest that reads' do
    break_manifest('{"version": "1.0')
    result = nil
    expect { result = described_class.install(lich_dir, root: payload) }.to output(/unreadable.*libeo install/).to_stderr
    expect(result[:copied]).to include('libeo.lic')
    expect(described_class.manifest(lich_dir)['files']).to include('libeo.lic')
  end

  it 'leaves no temporary manifest behind' do
    described_class.install(lich_dir, root: payload)
    expect(Dir.children(File.join(lich_dir, 'scripts'))).not_to include("#{described_class::MANIFEST}.tmp")
  end

  it 'keeps the old install and manifest when a copy fails, and removes stale files only after the copies' do
    described_class.install(lich_dir, root: payload(parts: %w[help.rb old.rb]))
    before = File.read(manifest_path)
    allow(FileUtils).to receive(:cp).and_raise(Errno::EACCES)
    expect { described_class.install(lich_dir, root: payload(version: '2.0.0', parts: %w[help.rb])) }.to raise_error(Errno::EACCES)
    expect(File.read(manifest_path)).to eq(before)
    expect(File.exist?(File.join(lich_dir, 'scripts', 'eo', 'old.rb'))).to be(true)
  end

  describe 'the command' do
    def run(*args)
      exe = File.expand_path('../exe/libeo', __dir__)
      Open3.capture3(RbConfig.ruby, exe, '--lich-dir', lich_dir, *args)
    end

    it 'says what is wrong in a line, and exits 1, without a backtrace' do
      break_manifest('{"version": "1.0')
      _out, err, status = run('uninstall')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('libeo: ').and include(manifest_path)
      expect(err).not_to include('.rb:')
    end

    it 'says a permission failure in a line, not a backtrace' do
      described_class.install(lich_dir, root: described_class.payload_root)
      target = File.join(lich_dir, 'scripts', 'eo', 'version.rb')
      File.write(target, '# changed')
      File.chmod(0o444, target)
      writable = begin
        File.write(target, '# changed')
        true
      rescue SystemCallError
        false
      end
      (File.chmod(0o666, target) && skip('this account can write a read-only file')) if writable
      _out, err, status = run('install')
      File.chmod(0o666, target)
      expect(status.exitstatus).to eq(1)
      expect(err).to match(/\Alibeo: .*(denied|Permission)/i)
      expect(err.lines.size).to eq(1)
    end
  end
end
