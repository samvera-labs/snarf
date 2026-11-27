# frozen_string_literal: true

require_relative 'config/boot'

run Snarf::Web.freeze.app
