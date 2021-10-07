module Timescale
  class Dimensions < ActiveRecord::Base
    self.table_name = "timescaledb_information.dimensions"

    attribute :time_interval, :interval
  end
end
