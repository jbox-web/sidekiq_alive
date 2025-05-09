# frozen_string_literal: true

require 'spec_helper'

begin
  # this is needed for spec to work with sidekiq >7
  require 'sidekiq/capsule'
rescue LoadError # rubocop:disable Lint/SuppressedException
end

RSpec.describe SidekiqAlive do
  context 'with configuration' do
    it 'has a version number' do
      expect(SidekiqAlive::VERSION).not_to(be_nil)
    end

    it 'configures the host from the #setup' do
      described_class.setup do |config|
        config.host = '1.2.3.4'
      end

      expect(described_class.config.host).to(eq('1.2.3.4'))
    end

    it 'configures the host from the SIDEKIQ_ALIVE_HOST ENV var' do
      ENV['SIDEKIQ_ALIVE_HOST'] = '1.2.3.4'

      described_class.config.set_defaults

      expect(described_class.config.host).to(eq('1.2.3.4'))

      ENV['SIDEKIQ_ALIVE_HOST'] = nil
    end

    it 'configures the port from the #setup' do
      described_class.setup do |config|
        config.port = 4567
      end

      expect(described_class.config.port).to(eq(4567))
    end

    it 'configures the port from the SIDEKIQ_ALIVE_PORT ENV var' do
      ENV['SIDEKIQ_ALIVE_PORT'] = '4567'

      described_class.config.set_defaults

      expect(described_class.config.port).to(eq('4567'))

      ENV['SIDEKIQ_ALIVE_PORT'] = nil
    end

    it 'configurations behave as expected' do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      k = described_class.config

      expect(k.host).to(eq('0.0.0.0'))
      k.host = '1.2.3.4'
      expect(k.host).to(eq('1.2.3.4'))

      expect(k.port).to(eq(7433))
      k.port = 4567
      expect(k.port).to(eq(4567))

      expect(k.liveness_key).to(eq('SIDEKIQ::LIVENESS_PROBE_TIMESTAMP'))
      k.liveness_key = 'key'
      expect(k.liveness_key).to(eq('key'))

      expect(k.time_to_live).to(eq(10 * 60))
      k.time_to_live = 2 * 60
      expect(k.time_to_live).to(eq(2 * 60))

      expect(k.callback.call).to be_nil
      k.callback = proc { 'hello' }
      expect(k.callback.call).to(eq('hello'))

      expect(k.queue_prefix).to(eq(:'sidekiq-alive'))
      k.queue_prefix = :other
      expect(k.queue_prefix).to(eq(:other))

      expect(k.shutdown_callback.call).to be_nil
      k.shutdown_callback = proc { 'hello' }
      expect(k.shutdown_callback.call).to(eq('hello'))
    end
  end

  context 'with redis' do
    # Older versions of sidekiq yielded Sidekiq module as configuration object
    # With sidekiq > 7, configuration is a separate class
    let(:sq_config) { Sidekiq.default_configuration }

    before do
      allow(Sidekiq).to receive(:server?).and_return(true)
      allow(sq_config).to(receive(:on))

      allow(sq_config).to(receive(:capsule).and_call_original)
    end

    it '::store_alive_key" stores key with the expected ttl' do
      redis = described_class.redis

      expect(redis.ttl(described_class.current_lifeness_key)).to(eq(-2))
      described_class.store_alive_key
      expect(redis.ttl(described_class.current_lifeness_key)).to(eq(described_class.config.time_to_live))
    end

    it '::current_lifeness_key' do
      expect(described_class.current_lifeness_key).to(include('::test-hostname'))
    end

    it '::hostname' do
      expect(described_class.hostname).to(eq('test-hostname'))
    end

    it '::alive?' do
      expect(described_class.alive?).to(be(false))
      described_class.store_alive_key
      expect(described_class.alive?).to(be(true))
    end

    describe '::start' do
      let(:queue_prefix) { :heathcheck }
      let(:queues) { Sidekiq.default_configuration.capsules[SidekiqAlive::CAPSULE_NAME].queues }

      before do
        allow(described_class).to(receive(:fork).and_return(1))
        allow(sq_config).to(receive(:on).with(:startup).and_yield)

        described_class.instance_variable_set(:@redis, nil)
      end

      it '::registered_instances' do
        described_class.start
        expect(described_class.registered_instances.count).to(eq(1))
        expect(described_class.registered_instances.first).to(include('test-hostname'))
      end

      it '::unregister_current_instance' do
        described_class.start

        expect(sq_config).to(have_received(:on).with(:quiet)) do |&arg| # rubocop:disable RSpec/MessageSpies
          arg.call

          expect(described_class.registered_instances.count).to(eq(0))
        end
      end

      it '::queues' do
        described_class.config.queue_prefix = queue_prefix

        described_class.start

        expect(queues.first).to(eq("#{queue_prefix}-test-hostname"))
      end
    end
  end
end
