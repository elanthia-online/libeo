# frozen_string_literal: true

require_relative 'eo_helper'
require_relative '../../scripts/eo/command'
require_relative '../../scripts/eo/inventory/hands'

RSpec.describe EO::Hands, '.take' do
  let(:torch) { Struct.new(:id, :name).new('777', 'torch') }
  let(:sent) { [] }

  # right_arm: the wound rank of the right arm; empty: the hands holding nothing
  def take_with(right_arm:, empty:)
    wounds = Struct.new(:rightArm, :rightHand, :leftArm, :leftHand).new(right_arm, 0, 0, 0)
    scars = Struct.new(:rightArm, :rightHand, :leftArm, :leftHand).new(0, 0, 0, 0)
    stub_const('Wounds', wounds)
    stub_const('Scars', scars)
    stub_const('Lich::Stash', Class.new do
      define_singleton_method(:empty_hand?) { |side| empty.include?(side) }
      define_singleton_method(:open_path_to) { |_item| nil }
    end)
    stub_const('GameObj', Class.new do
      hand = Struct.new(:id, :side)
      define_singleton_method(:right_hand) { hand.new(empty.include?(:right) ? nil : '1', :right) }
      define_singleton_method(:left_hand) { hand.new(empty.include?(:left) ? nil : '2', :left) }
    end)
    allow(EO).to receive(:result) do |cmd, _|
      sent << cmd
      'You grab a torch.'
    end
    allow(described_class).to receive_messages(holding?: true, checkright: !empty.include?(:right), checkleft: !empty.include?(:left))
    allow(described_class).to receive(:waitrt?)
    described_class.take(torch, stow: ->(obj) { empty << (obj.side) })
  end

  it 'takes into the right hand when it is empty and sound' do
    expect(take_with(right_arm: 0, empty: %i[right left])).to eq(:held)
    expect(sent).to eq(['_drag #777 right'])
  end

  it 'takes into the left hand when the right arm is crippled, both hands being empty' do
    expect(take_with(right_arm: 3, empty: %i[right left])).to eq(:held)
    expect(sent).to eq(['_drag #777 left'])
  end

  it 'takes into the left hand when the right arm is crippled and only the right hand is empty' do
    expect(take_with(right_arm: 3, empty: %i[right])).to eq(:held)
    expect(sent).to eq(['_drag #777 left'])
  end
end
