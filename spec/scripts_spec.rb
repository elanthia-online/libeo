# frozen_string_literal: true

require_relative 'spec_helper'

# The scripts cannot run outside Lich, but what they ask of the library can
# be checked: every EO method a script names is one the library has, and the
# version it requires is one this library satisfies.
RSpec.describe 'the scripts' do
  root = File.expand_path('../scripts', __dir__)
  scripts = Dir[File.join(root, '*.lic')].reject { |path| File.basename(path) == 'libeo.lic' }

  before(:all) do
    loader = File.read(File.join(root, 'libeo.lic'))
    parts = loader[/^parts = %w\[(.*?)\]/m, 1].split
    parts.each { |part| require File.join(root, 'eo', part) }
  end

  scripts.each do |path|
    name = File.basename(path)
    # comments and the header are not calls
    code = File.read(path).gsub(/^=begin.*?^=end/m, '').gsub(/#[^{].*$/, '')

    describe name do
      it 'names only methods the library has' do
        missing = code.scan(/\b(EO(?:::[A-Z]\w*)*)\.([a-z_]\w*[?!]?)/).uniq.reject do |const, method|
          Object.const_get(const).respond_to?(method)
        rescue NameError
          false
        end
        expect(missing.map { |const, method| "#{const}.#{method}" }).to be_empty
      end

      it 'requires a libeo version this library is' do
        wanted = code[/EO\.require\('([\d.]+)'\)/, 1]
        expect(wanted).not_to be_nil
        expect(Gem::Version.new(wanted)).to be <= Gem::Version.new(EO::VERSION)
      end
    end
  end
end
