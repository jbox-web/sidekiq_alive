# frozen_string_literal: true

module SidekiqAlive
  module Redis
    class << self
      def adapter
        Redis::RedisClientGem.new
      end
    end
  end
end
