require 'active_record/connection_adapters/postgresql_adapter'

# Useful methods to run TimescaleDB in you Ruby app.
module Timescale
  # Migration helpers can help you to setup hypertables by default.
  module MigrationHelpers
    # create_table can receive `hypertable` argument
    # @example
    #  options = {
    #    time_column: 'created_at',
    #    chunk_time_interval: '1 min',
    #    compress_segmentby: 'identifier',
    #    compress_orderby: 'created_at',
    #    compression_interval: '7 days'
    #  }
    #
    #  create_table(:events, id: false, hypertable: options) do |t|
    #    t.string :identifier, null: false
    #    t.jsonb :payload
    #    t.timestamps
    #  end
    def create_table(table_name, id: :primary_key, primary_key: nil, force: nil, **options)
      super
      setup_hypertable_options(table_name, **options[:hypertable]) if options.key?(:hypertable)
    end

    # Setup hypertable from options
    # @see create_table with the hypertable options.
    def setup_hypertable_options(table_name,
                                 time_column: 'created_at',
                                 chunk_time_interval: '1 week',
                                 compress_segmentby: nil,
                                 compress_orderby: 'created_at',
                                 compression_interval: nil
                                )

      ActiveRecord::Base.logger = Logger.new(STDOUT)
      execute "SELECT create_hypertable('#{table_name}', '#{time_column}', chunk_time_interval => INTERVAL '#{chunk_time_interval}')"

      if compress_segmentby
        execute <<~SQL
        ALTER TABLE #{table_name} SET (
          timescaledb.compress,
          timescaledb.compress_orderby = '#{compress_orderby}',
          timescaledb.compress_segmentby = '#{compress_segmentby}'
        )
        SQL
      end
      if compression_interval
        execute "SELECT add_compression_policy('#{table_name}', INTERVAL '#{compression_interval}')"
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.include(Timescale::MigrationHelpers)
