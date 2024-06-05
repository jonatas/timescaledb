module Timescaledb
  class ConnectionNotEstablishedError < StandardError; end

  module_function
  
  # @param [String] config with the postgres connection string.
  def establish_connection(config)
    Connection.instance.config = config
  end

  # @param [PG::Connection] to use it directly from a raw connection
  def use_connection conn
    Connection.instance.use_connection conn
  end

  def connection
    raise ConnectionNotEstablishedError.new unless Connection.instance.connected?

    Connection.instance
  end
end
