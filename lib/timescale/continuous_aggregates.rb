module Timescale
  class ContinuousAggregate < ActiveRecord::Base
    self.table_name = "timescaledb_information.continuous_aggregates"
    self.primary_key = 'materialization_hypertable_name'

    has_many :jobs, foreign_key: "hypertable_name",
      class_name: "Timescale::Job"

    has_many :chunks, foreign_key: "hypertable_name",
      class_name: "Timescale::Chunk"

    scope :resume, -> do
      {
        total: count
      }
    end
  end
  ContinuousAggregates = ContinuousAggregate
end
