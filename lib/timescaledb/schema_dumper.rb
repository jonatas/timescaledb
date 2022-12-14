require 'active_record/connection_adapters/postgresql_adapter'
require 'active_support/core_ext/string/indent'

module Timescaledb
  module SchemaDumper
    def tables(stream)
      super # This will call #table for each table in the database
      views(stream) unless defined?(Scenic) # Don't call this twice if we're using Scenic

      return unless Timescaledb::Hypertable.table_exists?

      timescale_hypertables(stream)
      timescale_retention_policies(stream)
    end

    def views(stream)
      return unless Timescaledb::ContinuousAggregates.table_exists?

      timescale_continuous_aggregates(stream) # Define these before any Scenic views that might use them
      super if defined?(super)
    end

    def timescale_hypertables(stream)
      stream.puts # Insert a blank line above the retention policies, for readability

      Timescaledb::Hypertable.find_each do |hypertable|
         timescale_hypertable(hypertable, stream)
      end
    end

    def timescale_retention_policies(stream)
      stream.puts # Insert a blank line above the retention policies, for readability

      @connection.tables.sort.each do |table_name|
        if Timescaledb::Hypertable.table_exists? &&
          (hypertable = Timescaledb::Hypertable.find_by(hypertable_name: table_name))
          timescale_retention_policy(hypertable, stream)
        end
      end
    end

    private

    def timescale_hypertable(hypertable, stream)
      dim = hypertable.main_dimension
      extra_settings = {
        time_column: "#{dim.column_name}",
        chunk_time_interval: "#{dim.time_interval.inspect}"
      }.merge(timescale_compression_settings_for(hypertable)).map {|k, v| %Q[#{k}: "#{v}"]}.join(", ")

      stream.puts %Q[  create_hypertable "#{hypertable.hypertable_name}", #{extra_settings}]
    end

    def timescale_retention_policy(hypertable, stream)
      hypertable.jobs.where(proc_name: "policy_retention").each do |job|
        stream.puts %Q[  create_retention_policy "#{job.hypertable_name}", interval: "#{job.config["drop_after"]}"]
      end
    end

    def timescale_compression_settings_for(hypertable)
      compression_settings = hypertable.compression_settings.each_with_object({}) do |setting, compression_settings|
        compression_settings[:compress_segmentby] = setting.attname if setting.segmentby_column_index

        if setting.orderby_column_index
          direction = setting.orderby_asc ? "ASC" : "DESC"
          compression_settings[:compress_orderby] = "#{setting.attname} #{direction}"
        end
      end

      hypertable.jobs.compression.each do |job|
        compression_settings[:compression_interval] = job.config["compress_after"]
      end
      compression_settings
    end

    def timescale_continuous_aggregates(stream)
      Timescaledb::ContinuousAggregates.all.each do |aggregate|
        opts = if (refresh_policy = aggregate.jobs.refresh_continuous_aggregate.first)
                 interval = timescale_interval(refresh_policy.schedule_interval)
                 end_offset = timescale_interval(refresh_policy.config["end_offset"])
                 start_offset = timescale_interval(refresh_policy.config["start_offset"])
                 %Q[, refresh_policies: { start_offset: "#{start_offset}", end_offset: "#{end_offset}", schedule_interval: "#{interval}"}]
               else
                 ""
               end

        stream.puts <<~AGG.indent(2)
          create_continuous_aggregate("#{aggregate.view_name}", <<-SQL#{opts})
            #{aggregate.view_definition.strip.gsub(/;$/, "")}
          SQL
        AGG
        stream.puts
      end
    end

    def timescale_interval(value)
      return "NULL" if value.nil? || value.to_s.downcase == "null"

      "INTERVAL '#{value}'"
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(Timescaledb::SchemaDumper)
