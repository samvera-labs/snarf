# frozen_string_literal: true

require 'rack/test'
require_relative '../../config/boot'

RSpec.describe Snarf::Web do
  include Rack::Test::Methods

  let(:dashboard) { nil }
  let(:app) do
    mounted = dashboard
    Class.new(described_class) { opts[:jobs_dashboard] = mounted }.app
  end

  it 'reports health' do
    get '/healthz'
    expect(last_response).to have_attributes(status: 200, body: '{"status":"ok"}')
  end

  describe '/jobs' do
    it 'is not found when the dashboard is not configured' do
      get '/jobs'
      expect(last_response.status).to eq(404)
    end

    context 'when the dashboard is configured' do
      let(:dashboard) { ->(env) { [200, {}, [env['SCRIPT_NAME']]] } }

      it 'mounts it at /jobs' do
        get '/jobs/queues'
        expect(last_response).to have_attributes(status: 200, body: '/jobs')
      end
    end
  end
end
