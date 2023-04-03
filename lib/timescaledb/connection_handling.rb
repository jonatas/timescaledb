module Timescaledb
  class ConnectionNotEstablishedError < StandardError; end

  # @param [String] config The postgres connection string.
  def establish_connection(config)
    Connection.instance.config = config
  end
  module_function :establish_connection

  def connection
    raise ConnectionNotEstablishedError.new unless Connection.instance.connected?

    Connection.instance
  end
  module_function :connection
end