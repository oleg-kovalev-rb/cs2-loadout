# typed: false
class ConnectionPool
  def self.new(size: nil, timeout: nil, &blk); end

  def with(timeout: nil, &blk); end
end
