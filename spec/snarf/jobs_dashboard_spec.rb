# frozen_string_literal: true

require 'rack/test'
require_relative '../../config/boot'

RSpec.describe Snarf::JobsDashboard do
  include Rack::Test::Methods

  let(:secret) { 'x' * 64 }

  describe '.from_env' do
    it 'is nil without credentials' do
      expect(described_class.from_env({})).to be_nil
    end

    it 'builds the dashboard when configured' do
      env = { 'JOBS_DASHBOARD_USERNAME' => 'admin', 'JOBS_DASHBOARD_PASSWORD' => 'pw', 'SESSION_SECRET' => secret }
      expect(described_class.from_env(env)).to respond_to(:call)
    end
  end

  describe '.build' do
    let(:app) do
      inner = ->(env) { [200, {}, [env.key?('rack.session').to_s]] }
      described_class.build(described_class::Config.new('admin', 'pw', secret), app: inner)
    end

    it 'rejects missing credentials' do
      get '/'
      expect(last_response.status).to eq(401)
    end

    it 'rejects a wrong password' do
      basic_authorize 'admin', 'wrong'
      get '/'
      expect(last_response.status).to eq(401)
    end

    it 'passes authorized requests through with a session' do
      basic_authorize 'admin', 'pw'
      get '/'
      expect(last_response).to have_attributes(status: 200, body: 'true')
    end
  end
end
