# frozen_string_literal: true

require 'rack/auth/basic'
require 'rack/session'
require 'sidekiq/web'

module Snarf
  # Sidekiq web UI behind HTTP basic auth; nil unless credentials and a session secret are configured.
  module JobsDashboard
    # Basic auth credentials and the session cookie secret (at least 64 bytes).
    Config = Data.define(:username, :password, :secret)

    def self.from_env(env)
      values = env.values_at('JOBS_DASHBOARD_USERNAME', 'JOBS_DASHBOARD_PASSWORD', 'SESSION_SECRET')
      return if values.any?(&:nil?)

      build(Config.new(*values))
    end

    def self.build(config, app: Sidekiq::Web)
      Rack::Builder.app do
        use Rack::Auth::Basic, 'Snarf jobs' do |user, pass|
          Rack::Utils.secure_compare(user, config.username) & Rack::Utils.secure_compare(pass, config.password)
        end
        use Rack::Session::Cookie, secrets: config.secret, same_site: :strict, max_age: 86_400
        run app
      end
    end
  end
end
