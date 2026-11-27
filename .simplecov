# frozen_string_literal: true

SimpleCov.configure do
  enable_coverage :branch
  cover 'lib/**/*.rb'
  minimum_coverage line: 100, branch: 100 if ENV['CI']
end
