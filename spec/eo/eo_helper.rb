# frozen_string_literal: true

require_relative '../spec_helper'

# The libeo files are loaded by libeo.lic inside Lich. Specs load the one
# file under test and stand in for the Lich globals it touches with
# stub_const, so nothing here needs a running Lich. Fakes more than one spec
# needs go in this file.
