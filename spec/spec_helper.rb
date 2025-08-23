# frozen_string_literal: true

require 'simplecov'
require 'simplecov_json_formatter'

# Start SimpleCov
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new([SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::JSONFormatter])
  add_filter 'spec/'
end

require 'sidekiq_alive'
require 'rspec-sidekiq'
require 'rack/test'

ENV['RACK_ENV'] = 'test'
ENV['HOSTNAME'] = 'test-hostname'

Sidekiq.logger.level = Logger::ERROR

# Configure RSpec
RSpec.configure do |config|
  config.color = true
  config.fail_fast = false

  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # disable monkey patching
  # see: https://relishapp.com/rspec/rspec-core/v/3-8/docs/configuration/zero-monkey-patching-mode
  config.disable_monkey_patching!

  config.raise_errors_for_deprecations!

  config.before do
    Sidekiq.redis(&:flushall)
    SidekiqAlive.config.set_defaults
  end
end
