module Timescaledb
  class Dimension < ActiveRecord::Base
    self.table_name = "timescaledb_information.dimensions"
    attribute :time_interval, :interval
  end
  Dimensions = Dimension
end
