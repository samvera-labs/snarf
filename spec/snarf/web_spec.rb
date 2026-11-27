# frozen_string_literal: true

require 'rack/test'
require_relative '../../config/boot'

RSpec.describe Snarf::Web do
  include Rack::Test::Methods

  def app = described_class.app

  it 'reports health' do
    get '/healthz'
    expect(last_response).to have_attributes(status: 200, body: '{"status":"ok"}')
  end
end
