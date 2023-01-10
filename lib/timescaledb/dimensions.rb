module Timescaledb
  class Dimension < ::Timescaledb::ApplicationRecord
    self.table_name = "timescaledb_information.dimensions"
#    attribute :time_interval, :interval
  end
  Dimensions = Dimension
end
