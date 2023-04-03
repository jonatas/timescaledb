require 'singleton'

module Timescaledb
  class Connection
    include Singleton

    attr_writer :config

    # @param [String] query The SQL raw query.
    # @param [Array] params The SQL query parameters.
    # @return [Array<OpenStruct>] The SQL result.
    def query(query, params = [])
      query = params.empty? ? connection.exec(query) : connection.exec_params(query, params)

      query.map(&OpenStruct.method(:new))
    end

    # @param [String] query The SQL raw query.
    # @param [Array] params The SQL query parameters.
    # @return [OpenStruct] The first SQL result.
    def query_first(query, params = [])
      query(query, params).first
    end

    # @param [String] query The SQL raw query.
    # @param [Array] params The SQL query parameters.
    # @return [Integr] The count value from SQL result.
    def query_count(query, params = [])
      query_first(query, params).count.to_i
    end

    # @param [Boolean] True if the connection singleton was configured, otherwise returns false.
    def connected?
      !@config.nil?
    end

    private

    def connection
      @connection ||= PG.connect(@config)
    end
  end
end