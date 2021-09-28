module Timescale
  class Hypertable < ActiveRecord::Base
    self.table_name = "timescaledb_information.hypertables"

    self.primary_key = "hypertable_name"

    has_many :jobs, foreign_key: "hypertable_name"
    has_many :chunks, foreign_key: "hypertable_name"

    has_many :compression_settings,
      foreign_key: "hypertable_name",
      class_name: "Timescale::CompressionSettings"

    has_many :continuous_aggregates,
      foreign_key: "hypertable_name",
      class_name: "Timescale::ContinuousAggregates"

    def chunks_detailed_size
      struct_from "SELECT * from chunks_detailed_size('#{self.hypertable_name}')"
    end

    def compression_stats
      struct_from("SELECT * from hypertable_compression_stats('#{self.hypertable_name}')").first || {}
    end

    def detailed_size
      struct_from("SELECT * FROM hypertable_detailed_size('#{self.hypertable_name}')").first
    end

    def before_total_bytes
      compression_stats["before_compression_total_bytes"] || detailed_size.total_bytes
    end

    def after_total_bytes
      compression_stats["after_compression_total_bytes"] || 0
    end

    private
    def struct_from(sql)
      self.class.connection.execute(sql).map(&OpenStruct.method(:new))
    end
  end
end
