module Timescale
  class ContinuousAggregates < ActiveRecord::Base
    self.table_name = "timescaledb_information.continuous_aggregates"
  end
end
