
module Timescale
  class Hypertable < ActiveRecord::Base
    self.table_name = "timescaledb_information.hypertables"
  end
end
