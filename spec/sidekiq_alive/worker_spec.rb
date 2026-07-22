# frozen_string_literal: true

require 'spec_helper'

RSpec.describe(SidekiqAlive::Worker) do
  subject(:worker) { described_class.new.perform }

  context 'when being executed in the same instance' do
    it 'stores alive key and requeues it self' do
      SidekiqAlive.register_current_instance
      expect(described_class).to(receive(:perform_in))
      n = 0
      SidekiqAlive.config.callback = proc { n = 2 }
      worker
      expect(n).to(eq(2))
      expect(SidekiqAlive.alive?).to(be(true))
    end
  end

  context 'when using custom liveness probe' do
    it 'on error' do
      # A raising probe must not write the key, but must still reschedule so
      # the heartbeat loop recovers on its own once the probe stops raising.
      expect(described_class).to(receive(:perform_in))

      n = 0
      SidekiqAlive.config.custom_liveness_probe = proc do
        n = 2
        raise 'Nop'
      end

      worker

      expect(n).to(eq(2))
      expect(SidekiqAlive.alive?).to(be(false))
    end

    it 'on returning false does not write the key but still reschedules' do
      expect(described_class).to(receive(:perform_in))
      SidekiqAlive.config.custom_liveness_probe = proc { false }

      worker

      expect(SidekiqAlive.alive?).to(be(false))
    end

    it 'on success' do
      expect(described_class).to(receive(:perform_in))
      n = 0
      SidekiqAlive.config.custom_liveness_probe = proc { n = 2 }
      worker

      expect(n).to(eq(2))
      expect(SidekiqAlive.alive?).to(be(true))
    end
  end
end
