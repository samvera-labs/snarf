# frozen_string_literal: true

require 'roda'

module Snarf
  # HTTP API.
  class Web < Roda
    plugin :common_logger, SemanticLogger['Web'], method: :info
    plugin :json

    route do |r|
      r.get 'healthz' do
        { status: 'ok' }
      end
    end
  end
end
