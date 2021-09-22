module Timescale
  class Hypertable < ActiveRecord::Base
    self.table_name = "timescaledb_information.hypertables"

    self.primary_key = "hypertable_name"

    has_many :jobs, foreign_key: "hypertable_name"
    has_many :chunks, foreign_key: "hypertable_name"

    has_many :compression_settings,
      foreign_key: "hypertable_name",
      class_name: "Timescale::CompressionSettings"

    def detailed_size
      struct_from "SELECT * from chunks_detailed_size('#{self.hypertable_name}')"
    end

    def compression_stats
      struct_from "SELECT * from hypertable_compression_stats('#{self.hypertable_name}')"
    end

    private
    def struct_from(sql)
      self.class.connection.execute(sql).map(&OpenStruct.method(:new))
    end
  end
end
