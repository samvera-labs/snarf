# frozen_string_literal: true

require_relative '../config/boot'

RSpec.describe 'Zeitwerk' do
  it 'eager loads all app files' do
    expect { Snarf.loader.eager_load(force: true) }.not_to raise_error
  end
end
