
module Timescaledb
  class Stats
    class JobStats
      # @param [Timescaledb:Connection] connection The PG connection.
      def initialize(connection = Timescaledb.connection)
        @connection = connection
      end

      delegate :query_first, to: :@connection

      # @return [Hash] The job_stats stats
      def to_h
        query_first(job_stats_query).to_h.transform_values(&:to_i)
      end

      private

      def job_stats_query
        <<-SQL
          SELECT SUM(total_successes)::INT AS success,
                 SUM(total_runs)::INT AS runs,
                 SUM(total_failures)::INT AS failures
          FROM timescaledb_information.job_stats
        SQL
      end
    end
  end
end