module Timescale
  class ContinuousAggregates < ActiveRecord::Base
    self.table_name = "timescaledb_information.continuous_aggregates"
    self.primary_key = 'materialization_hypertable_name'

    has_many :jobs, foreign_key: "hypertable_name",
      class_name: "Timescale::Job"
  end
end
