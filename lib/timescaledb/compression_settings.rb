module Timescaledb
  class CompressionSetting < ::Timescaledb::ApplicationRecord
    self.table_name = "timescaledb_information.compression_settings"
    belongs_to :hypertable, foreign_key: :hypertable_name
  end
  CompressionSettings = CompressionSetting
end
