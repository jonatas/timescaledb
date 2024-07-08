def create_hypertable(table_name:, time_column_name: :created_at, options: {})
  create_table(table_name.to_sym, id: false, hypertable: options) do |t|
    t.string :identifier, null: false
    t.jsonb :payload
    t.timestamp time_column_name.to_sym
  end
end

def setup_tables
  ActiveRecord::Schema.define(version: 1) do
    create_hypertable(
      table_name: :events,
      time_column_name: :created_at,
      options: {
        time_column: 'created_at',
        chunk_time_interval: '1 min',
        compress_segmentby: 'identifier',
        compression_interval: '7 days'
      }
    )

    create_hypertable(table_name: :hypertable_with_no_options)

    create_hypertable(
      table_name: :hypertable_with_options,
      time_column_name: :timestamp,
      options: {
        time_column: 'timestamp',
        chunk_time_interval: '1 min',
        compress_segmentby: 'identifier',
        compress_orderby: 'timestamp',
        compression_interval: '7 days'
      }
    )

    create_hypertable(
      table_name: :hypertable_with_custom_time_column,
      time_column_name: :timestamp,
      options: { time_column: 'timestamp' }
    )

    create_table(:hypertable_with_id_partitioning, hypertable: {
      time_column: 'id',
      chunk_time_interval: 1_000_000
    })

    create_table(:non_hypertables) do |t|
      t.string :name
    end
  end
end

def teardown_tables
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table, force: :cascade)
  end
end
