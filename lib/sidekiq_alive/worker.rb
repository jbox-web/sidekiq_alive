# frozen_string_literal: true

module SidekiqAlive
  class Worker
    include Sidekiq::Worker

    sidekiq_options retry: false

    # Passing the hostname argument it's only for debugging enqueued jobs
    def perform(_hostname = SidekiqAlive.hostname)
      # A failing probe (returning false/nil or raising) must not write the key,
      # but it must NOT stop the heartbeat: we always reschedule in `ensure` so
      # the loop self-heals once the probe recovers, without needing a restart.
      write_living_probe if probe_passing?
    ensure
      # schedules next living probe
      self.class.perform_in(reschedule_interval, current_hostname)
    end

    def probe_passing?
      config.custom_liveness_probe.call
    rescue StandardError => e
      SidekiqAlive.logger.warn("[SidekiqAlive] custom liveness probe raised: #{e.message}")
      false
    end

    def write_living_probe
      # Write liveness probe
      SidekiqAlive.store_alive_key
      # Increment ttl for current registered instance
      SidekiqAlive.register_current_instance
      # after callbacks
      begin
        config.callback.call
      rescue StandardError => e
        SidekiqAlive.logger.warn("[SidekiqAlive] callback raised: #{e.message}")
      end
    end

    # Floored to 1s: integer division of a small time_to_live can yield 0,
    # which would requeue the worker in a tight loop hammering Redis.
    def reschedule_interval
      [config.time_to_live / 2, 1].max
    end

    def current_hostname
      SidekiqAlive.hostname
    end

    def config
      SidekiqAlive.config
    end
  end
end
