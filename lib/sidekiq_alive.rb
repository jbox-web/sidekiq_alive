# frozen_string_literal: true

# require ruby dependencies
require 'singleton'

# require external dependencies
require 'rackup'
require 'sidekiq'
require 'sidekiq/api'
require 'zeitwerk'

# load zeitwerk
Zeitwerk::Loader.for_gem.tap do |loader| # rubocop:disable Style/SymbolProc
  loader.setup
end

module SidekiqAlive
  HOSTNAME_REGISTRY = 'sidekiq-alive-hostnames'
  CAPSULE_NAME = 'sidekiq-alive'

  class << self
    def start # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      Sidekiq.configure_server do |sq_config|
        sq_config.on(:startup) do
          SidekiqAlive::Worker.sidekiq_options(queue: current_queue)

          sq_config.capsule(CAPSULE_NAME) do |cap|
            cap.concurrency = 2
            cap.queues = [current_queue]
          end

          logger.info(startup_info)

          register_current_instance

          store_alive_key
          # Passing the hostname argument it's only for debugging enqueued jobs
          SidekiqAlive::Worker.perform_async(hostname)
          @server_pid = fork { SidekiqAlive::Server.run! }

          logger.info(successful_startup_text)
        end

        sq_config.on(:quiet) do
          unregister_current_instance
          config.shutdown_callback.call
        end

        sq_config.on(:shutdown) do
          Process.kill('TERM', @server_pid) unless @server_pid.nil?
          Process.wait(@server_pid) unless @server_pid.nil?

          unregister_current_instance
          config.shutdown_callback.call
        end
      end
    end

    def current_queue
      "#{config.queue_prefix}-#{hostname}"
    end

    def register_current_instance
      register_instance(current_instance_register_key)
    end

    def unregister_current_instance
      # Delete any pending jobs for this instance
      logger.info(shutdown_info)
      purge_pending_jobs
      redis.zrem(HOSTNAME_REGISTRY, current_instance_register_key)
    end

    def registered_instances
      # before we return we make sure we expire old keys
      expire_old_keys
      redis.zrange(HOSTNAME_REGISTRY, 0, -1)
    end

    def purge_pending_jobs
      schedule_set = Sidekiq::ScheduledSet.new
      jobs = schedule_set.scan('"class":"SidekiqAlive::Worker"').select { |job| job.queue == current_queue }

      logger.info("[SidekiqAlive] Purging #{jobs.count} pending for #{hostname}")
      jobs.each(&:delete)

      logger.info("[SidekiqAlive] Removing queue #{current_queue}")
      Sidekiq::Queue.new(current_queue).clear
    end

    def current_instance_register_key
      "#{config.registered_instance_key}::#{hostname}"
    end

    def current_instance_registered?
      redis.get(current_instance_register_key)
    end

    def store_alive_key
      redis.set(current_lifeness_key, time: Time.now.to_i, ex: config.time_to_live.to_i)
    end

    def redis
      @redis ||= Redis.adapter
    end

    def alive?
      redis.ttl(current_lifeness_key) != -2
    end

    # CONFIG ---------------------------------------

    def setup
      yield(config)
    end

    def logger
      config.logger || Sidekiq.logger
    end

    def config
      @config ||= SidekiqAlive::Config.instance
    end

    def current_lifeness_key
      "#{config.liveness_key}::#{hostname}"
    end

    def hostname
      ENV['SIDEKIQ_ALIVE_HOSTNAME'] || ENV['HOSTNAME'] || 'HOSTNAME_NOT_SET'
    end

    def shutdown_info
      'Shutting down sidekiq-alive!'
    end

    def startup_info
      info = {
        hostname: hostname,
        port: config.port,
        ttl: config.time_to_live,
        queue: current_queue,
        register_set: HOSTNAME_REGISTRY,
        liveness_key: current_lifeness_key,
        register_key: current_instance_register_key,
      }

      "Starting sidekiq-alive: #{info}"
    end

    def successful_startup_text
      'Successfully started sidekiq-alive, registered with key: ' \
        "#{current_instance_register_key} on set #{HOSTNAME_REGISTRY}"
    end

    def expire_old_keys
      # we get every key that should be expired by now
      keys_to_expire = redis.zrangebyscore(HOSTNAME_REGISTRY, 0, Time.now.to_i)
      # then we remove it
      keys_to_expire.each { |key| redis.zrem(HOSTNAME_REGISTRY, key) }
    end

    def register_instance(instance_name)
      expiration = Time.now.to_i + config.registration_ttl.to_i
      redis.zadd(HOSTNAME_REGISTRY, expiration, instance_name)
      expire_old_keys
    end
  end
end

SidekiqAlive.start unless ENV.fetch('DISABLE_SIDEKIQ_ALIVE', '').casecmp('true').zero?
