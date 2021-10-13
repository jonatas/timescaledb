module Timescale
  class Dimensions < ActiveRecord::Base
    self.table_name = "timescaledb_information.dimensions"
  end
end
