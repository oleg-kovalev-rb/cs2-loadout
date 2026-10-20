# typed: false
class ConnectionPool
  module ForkTracker
  end

  def self.new(size: nil, timeout: nil, &blk); end

  def with(timeout: nil, &blk); end
end
