# frozen_string_literal: true

require 'bundler/setup'
require 'semantic_logger'
require 'sequel'
require 'sidekiq'
require 'zeitwerk'

# Batch ingest service for Postgres, Solr, and file storage.
module Snarf
  def self.env = ENV.fetch('APP_ENV', 'development')
  def self.root = File.expand_path('..', __dir__)
  def self.loader = @loader ||= Zeitwerk::Loader.new
end

SemanticLogger.application = 'snarf'
SemanticLogger.default_level = ENV.fetch('LOG_LEVEL', 'info').to_sym
SemanticLogger.add_appender(io: $stdout, formatter: ENV.fetch('LOG_FORMAT', 'json').to_sym)

Snarf::DB = Sequel.connect(
  ENV.fetch('DATABASE_URL') do
    raise KeyError, 'DATABASE_URL is required in production' if Snarf.env == 'production'

    "postgres://localhost/snarf_#{Snarf.env}"
  end,
  max_connections: Integer(ENV.fetch('DB_POOL', 5)),
  test: false,
  logger: SemanticLogger['Sequel'],
  sql_log_level: :debug,
  log_warn_duration: 0.5
)

Sidekiq.configure_server { |config| config.logger = SemanticLogger['Sidekiq'] }
Sidekiq.configure_client { |config| config.logger = SemanticLogger['Sidekiq'] }

Snarf.loader.tap do |loader|
  loader.push_dir(File.join(Snarf.root, 'lib/snarf'), namespace: Snarf)
  loader.ignore(File.join(Snarf.root, 'lib/snarf/routes'))
  loader.setup
end
