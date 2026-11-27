# frozen_string_literal: true

threads_count = Integer(ENV.fetch('PUMA_THREADS', 3))
threads threads_count, threads_count
port Integer(ENV.fetch('PORT', 3000))
workers Integer(ENV.fetch('WEB_CONCURRENCY', 0))
preload_app!

before_fork { Snarf::DB.disconnect }
before_worker_boot { SemanticLogger.reopen }
