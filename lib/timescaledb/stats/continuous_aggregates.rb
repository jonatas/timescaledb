
module Timescaledb
  class Stats
    class ContinuousAggregates
      # @param [Timescaledb:Connection] connection The PG connection.
      def initialize(connection = Timescaledb.connection)
        @connection = connection
      end

      delegate :query_count, to: :@connection

      # @return [Hash] The continuous_aggregates stats
      def to_h
        { total: total }
      end

      private

      def total
        query_count('SELECT COUNT(1) FROM timescaledb_information.continuous_aggregates')
      end
    end
  end
end