module Timescale
  class CompressionSetting < ActiveRecord::Base
    self.table_name = "timescaledb_information.compression_settings"
    belongs_to :hypertable, foreign_key: :hypertable_name
  end
  CompressionSettings = CompressionSetting
end
