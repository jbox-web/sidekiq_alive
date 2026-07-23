# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqAlive::Redis do
  let(:redis) { described_class.adapter }

  it 'Works' do # rubocop:disable RSpec/ExampleWording
    time = Time.now.to_s
    redis.set('hello', time: time, ex: 60)
    expect(redis.ttl('hello') > 1).to(be(true))
    expect(redis.get('hello')).to(eq(time))
    redis.zadd('test_set', Time.now.to_i, 'test-key-1')
    redis.zadd('test_set', Time.now.to_i, 'test-key-2')
    expect(redis.zrange('test_set', 0, -1)).to(eq(%w[test-key-1 test-key-2]))
    expect(redis.zrem('test_set', 'test-key-1')) # rubocop:disable RSpec/VoidExpect
    expect(redis.zrange('test_set', 0, -1)).to(eq(['test-key-2']))
  end

  it 'deletes a key' do
    redis.set('to-delete', time: Time.now.to_s, ex: 60)
    redis.delete('to-delete')
    expect(redis.ttl('to-delete')).to(eq(-2))
  end

  describe SidekiqAlive::Redis::Base do
    subject(:base) { described_class.new }

    # Base is the abstract interface; every write operation must be overridden by
    # a concrete adapter. Calling them on Base directly signals a broken adapter.
    {
      set: [],
      zadd: %w[set-key 1 key],
      zrange: ['set-key', 0, -1],
      zrangebyscore: %w[set-key 0 1],
      zrem: %w[set-key key],
      delete: ['key'],
    }.each do |method, args|
      it "##{method} raises NotImplementedError" do
        expect { base.public_send(method, *args) }.to(raise_error(NotImplementedError))
      end
    end
  end
end
