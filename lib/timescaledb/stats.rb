require_relative './stats/continuous_aggregates'
require_relative './stats/hypertables'
require_relative './stats/job_stats'

module Timescaledb
  class Stats
    # @param [Array<OpenStruct>] hypertables The list of hypertables.
    # @param [Timescaledb:Connection] connection The PG connection.
    def initialize(hypertables = [], connection = Timescaledb.connection)
      @hypertables = hypertables
      @connection = connection
    end

    def to_h
      {
        hypertables: Hypertables.new(@hypertables).to_h,
        continuous_aggregates: ContinuousAggregates.new.to_h,
        jobs_stats: JobStats.new.to_h
      }
    end
  end
end
