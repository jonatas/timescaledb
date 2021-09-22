module Timescale
  class CompressionSettings < ActiveRecord::Base
    self.table_name = "timescaledb_information.compression_settings"
  end
end
