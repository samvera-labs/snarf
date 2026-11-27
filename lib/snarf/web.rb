# frozen_string_literal: true

require 'roda'

module Snarf
  # HTTP API.
  class Web < Roda
    opts[:jobs_dashboard] = JobsDashboard.from_env(ENV)

    plugin :common_logger, SemanticLogger['Web'], method: :info
    plugin :json

    route do |r|
      r.get 'healthz' do
        { status: 'ok' }
      end

      r.on 'jobs' do
        dashboard = opts[:jobs_dashboard]
        r.run dashboard if dashboard
      end
    end
  end
end
