module Timescaledb
  class Dimension < ActiveRecord::Base
    self.table_name = "timescaledb_information.dimensions"
  end
  Dimensions = Dimension
end
