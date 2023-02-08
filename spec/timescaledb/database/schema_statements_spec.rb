# frozen_string_literal: true

require 'spec_helper'

require 'timescaledb/database'

RSpec.describe Timescaledb::Database do
  describe '.create_hypertable_sql' do
    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.create_hypertable_sql('events', 'created_at')
        ).to eq("SELECT create_hypertable('events', 'created_at');")
      end
    end

    context 'when passing both partitioning_column and number_partitions' do
      it 'returns expected SQL' do
        expect(
          described_class.create_hypertable_sql('events', 'created_at', partitioning_column: 'category', number_partitions: 3)
        ).to eq("SELECT create_hypertable('events', 'created_at', 'category', 3);")
      end
    end

    context 'when passing interval params' do
      it 'returns expected SQL' do
        expect(
          described_class.create_hypertable_sql('events', 'created_at', chunk_time_interval: '1 week')
        ).to eq("SELECT create_hypertable('events', 'created_at', chunk_time_interval => INTERVAL '1 week');")
      end
    end

    context 'when passing boolean params' do
      it 'returns expected SQL' do
        optional_params = { if_not_exists: true, create_default_indexes: true, migrate_data: false, distributed: false }

        expect(
          described_class.create_hypertable_sql('events', 'created_at', **optional_params)
        ).to eq("SELECT create_hypertable('events', 'created_at', if_not_exists => 'TRUE', create_default_indexes => 'TRUE', migrate_data => 'FALSE', distributed => 'FALSE');")
      end
    end

    context 'when passing integer params' do
      it 'returns expected SQL' do
        expect(
          described_class.create_hypertable_sql('events', 'created_at', replication_factor: 3)
        ).to eq("SELECT create_hypertable('events', 'created_at', replication_factor => 3);")
      end
    end

    context 'when passing string params' do
      it 'returns expected SQL' do
        optional_params = {
          partitioning_func: 'category_func',
          associated_schema_name: '_timescaledb',
          associated_table_prefix: '_hypertable',
          time_partitioning_func: 'created_at_func'
        }

        expect(
          described_class.create_hypertable_sql('events', 'created_at', **optional_params)
        ).to eq("SELECT create_hypertable('events', 'created_at', partitioning_func => 'category_func', associated_schema_name => '_timescaledb', associated_table_prefix => '_hypertable', time_partitioning_func => 'created_at_func');")
      end
    end

    context 'when passing a mix of param types' do
      it 'returns expected SQL' do
        optional_params = {
          if_not_exists: true,
          replication_factor: 3,
          partitioning_column: 'category',
          number_partitions: 3,
          partitioning_func: 'category_func',
          distributed: false
        }

        expect(
          described_class.create_hypertable_sql('events', 'created_at', **optional_params)
        ).to eq("SELECT create_hypertable('events', 'created_at', 'category', 3, if_not_exists => 'TRUE', replication_factor => 3, partitioning_func => 'category_func', distributed => 'FALSE');")
      end
    end
  end

  describe '.enable_hypertable_compression_sql' do
    context 'when passing only hypertable params' do
      it 'returns expected SQL' do
        expect(
          described_class.enable_hypertable_compression_sql('events')
        ).to eq("ALTER TABLE events SET (timescaledb.compress);")
      end
    end

    context 'when passing compress_orderby' do
      it 'returns expected SQL' do
        expect(
          described_class.enable_hypertable_compression_sql('events', compress_orderby: 'timestamp DESC')
        ).to eq("ALTER TABLE events SET (timescaledb.compress, timescaledb.compress_orderby = 'timestamp DESC');")
      end
    end

    context 'when passing compress_segmentby' do
      it 'returns expected SQL' do
        expect(
          described_class.enable_hypertable_compression_sql('events', compress_segmentby: 'identifier')
        ).to eq("ALTER TABLE events SET (timescaledb.compress, timescaledb.compress_segmentby = 'identifier');")
      end
    end

    context 'when passing all params' do
      it 'returns expected SQL' do
        expect(
          described_class.enable_hypertable_compression_sql('events', compress_orderby: 'timestamp DESC', compress_segmentby: 'identifier')
        ).to eq("ALTER TABLE events SET (timescaledb.compress, timescaledb.compress_orderby = 'timestamp DESC', timescaledb.compress_segmentby = 'identifier');")
      end
    end
  end

  describe '.disable_hypertable_compression_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.disable_hypertable_compression_sql('events')
      ).to eq("ALTER TABLE events SET (timescaledb.compress = FALSE);")
    end
  end

  describe '.add_compression_policy_sql' do
    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.add_compression_policy_sql('events', '1 day')
        ).to eq("SELECT add_compression_policy('events', INTERVAL '1 day');")
      end
    end

    context 'when passing initial_start param' do
      it 'returns expected SQL' do
        expect(
          described_class.add_compression_policy_sql('events', '1 day', initial_start: '2023-01-01 10:00:00')
        ).to eq("SELECT add_compression_policy('events', INTERVAL '1 day', initial_start => '2023-01-01 10:00:00');")
      end
    end

    context 'when passing timezone param' do
      it 'returns expected SQL' do
        expect(
          described_class.add_compression_policy_sql('events', '1 day', timezone: 'America/Montevideo')
        ).to eq("SELECT add_compression_policy('events', INTERVAL '1 day', timezone => 'America/Montevideo');")
      end
    end

    context 'when passing all params' do
      it 'returns expected SQL' do
        expect(
          described_class.add_compression_policy_sql('events', '1 day', initial_start: '2023-01-01 10:00:00', timezone: 'America/Montevideo', if_not_exists: false)
        ).to eq("SELECT add_compression_policy('events', INTERVAL '1 day', initial_start => '2023-01-01 10:00:00', timezone => 'America/Montevideo', if_not_exists => 'FALSE');")
      end
    end
  end

  describe '.remove_compression_policy_sql' do
    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.remove_compression_policy_sql('events')
        ).to eq("SELECT remove_compression_policy('events');")
      end
    end

    context 'when passing if_exists param' do
      it 'returns expected SQL' do
        expect(
          described_class.remove_compression_policy_sql('events', if_exists: true)
        ).to eq("SELECT remove_compression_policy('events', if_exists => 'TRUE');")
      end
    end
  end

  describe '.add_retention_policy_sql' do
    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.add_retention_policy_sql('events', '1 day')
        ).to eq("SELECT add_retention_policy('events', INTERVAL '1 day');")
      end
    end

    context 'when passing initial_start param' do
      it 'returns expected SQL' do
        expect(
          described_class.add_retention_policy_sql('events', '1 day', initial_start: '2023-01-01 10:00:00')
        ).to eq("SELECT add_retention_policy('events', INTERVAL '1 day', initial_start => '2023-01-01 10:00:00');")
      end
    end

    context 'when passing timezone param' do
      it 'returns expected SQL' do
        expect(
          described_class.add_retention_policy_sql('events', '1 day', timezone: 'America/Montevideo')
        ).to eq("SELECT add_retention_policy('events', INTERVAL '1 day', timezone => 'America/Montevideo');")
      end
    end

    context 'when passing all params' do
      it 'returns expected SQL' do
        expect(
          described_class.add_retention_policy_sql('events', '1 day', initial_start: '2023-01-01 10:00:00', timezone: 'America/Montevideo', if_not_exists: false)
        ).to eq("SELECT add_retention_policy('events', INTERVAL '1 day', initial_start => '2023-01-01 10:00:00', timezone => 'America/Montevideo', if_not_exists => 'FALSE');")
      end
    end
  end

  describe '.remove_retention_policy_sql' do
    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.remove_retention_policy_sql('events')
        ).to eq("SELECT remove_retention_policy('events');")
      end
    end

    context 'when passing if_exists param' do
      it 'returns expected SQL' do
        expect(
          described_class.remove_retention_policy_sql('events', if_exists: true)
        ).to eq("SELECT remove_retention_policy('events', if_exists => 'TRUE');")
      end
    end
  end

  describe '.add_reorder_policy_sql' do
    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.add_reorder_policy_sql('events', 'index_name')
        ).to eq("SELECT add_reorder_policy('events', 'index_name');")
      end
    end

    context 'when passing initial_start param' do
      it 'returns expected SQL' do
        expect(
          described_class.add_reorder_policy_sql('events', 'index_name', initial_start: '2023-01-01 10:00:00')
        ).to eq("SELECT add_reorder_policy('events', 'index_name', initial_start => '2023-01-01 10:00:00');")
      end
    end

    context 'when passing timezone param' do
      it 'returns expected SQL' do
        expect(
          described_class.add_reorder_policy_sql('events', 'index_name', timezone: 'America/Montevideo')
        ).to eq("SELECT add_reorder_policy('events', 'index_name', timezone => 'America/Montevideo');")
      end
    end

    context 'when passing all params' do
      it 'returns expected SQL' do
        expect(
          described_class.add_reorder_policy_sql('events', 'index_name', initial_start: '2023-01-01 10:00:00', timezone: 'America/Montevideo', if_not_exists: false)
        ).to eq("SELECT add_reorder_policy('events', 'index_name', initial_start => '2023-01-01 10:00:00', timezone => 'America/Montevideo', if_not_exists => 'FALSE');")
      end
    end
  end

  describe '.remove_reorder_policy_sql' do
    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.remove_reorder_policy_sql('events')
        ).to eq("SELECT remove_reorder_policy('events');")
      end
    end

    context 'when passing if_exists param' do
      it 'returns expected SQL' do
        expect(
          described_class.remove_reorder_policy_sql('events', if_exists: true)
        ).to eq("SELECT remove_reorder_policy('events', if_exists => 'TRUE');")
      end
    end
  end

  describe '.create_continuous_aggregate_sql' do
    let(:sql) {
      <<~SQL
        SELECT time_bucket('1 day', created_at) bucket, COUNT(*)
        FROM activity
        GROUP BY bucket
      SQL
    }

    context 'when passing only required params' do
      it 'returns expected SQL' do
        expected_sql = <<~SQL
          CREATE MATERIALIZED VIEW activity_counts
          WITH (timescaledb.continuous) AS
          SELECT time_bucket('1 day', created_at) bucket, COUNT(*)
          FROM activity
          GROUP BY bucket
          WITH DATA;
        SQL

        expect(
          described_class.create_continuous_aggregate_sql('activity_counts', sql)
        ).to eq(expected_sql)
      end
    end

    context 'when passing with_no_data param' do
      it 'returns expected SQL' do
        expected_sql = <<~SQL
          CREATE MATERIALIZED VIEW activity_counts
          WITH (timescaledb.continuous) AS
          SELECT time_bucket('1 day', created_at) bucket, COUNT(*)
          FROM activity
          GROUP BY bucket
          WITH NO DATA;
        SQL

        expect(
          described_class.create_continuous_aggregate_sql('activity_counts', sql, with_no_data: true)
        ).to eq(expected_sql)
      end
    end
  end

  describe '.drop_continuous_aggregate_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.drop_continuous_aggregate_sql('activity_counts')
      ).to eq("DROP MATERIALIZED VIEW activity_counts;")
    end

    context 'when passing cascade true' do
      it 'returns expected SQL' do
        expect(
          described_class.drop_continuous_aggregate_sql('activity_counts', cascade: true)
        ).to eq("DROP MATERIALIZED VIEW activity_counts CASCADE;")
      end
    end
  end

  describe '.add_continuous_aggregate_policy_sql' do
    context 'when missing required params' do
      it 'raises ArgumentError' do
        expect {
          described_class.add_continuous_aggregate_policy_sql('activity_counts')
        }.to raise_error(ArgumentError, 'missing keyword: :schedule_interval')
      end
    end

    context 'when passing only required params' do
      it 'returns expected SQL' do
        expect(
          described_class.add_continuous_aggregate_policy_sql(
            'activity_counts',
            start_offset: '1 month',
            end_offset: '1 day',
            schedule_interval: '1 hour'
          )
        ).to eq("SELECT add_continuous_aggregate_policy('activity_counts', start_offset => INTERVAL '1 month', end_offset => INTERVAL '1 day', schedule_interval => INTERVAL '1 hour');")
      end

      context 'having null offset values' do
        it 'returns expected SQL' do
          expect(
            described_class.add_continuous_aggregate_policy_sql(
              'activity_counts',
              start_offset: nil,
              end_offset: nil,
              schedule_interval: '1 hour'
            )
          ).to eq("SELECT add_continuous_aggregate_policy('activity_counts', start_offset => NULL, end_offset => NULL, schedule_interval => INTERVAL '1 hour');")
        end
      end
    end

    context 'when passing initial_start' do
      it 'returns expected SQL' do
        expect(
          described_class.add_continuous_aggregate_policy_sql(
            'activity_counts',
            start_offset: nil,
            end_offset: nil,
            schedule_interval: '1 hour',
            initial_start: "2023-02-08 20:00:00"
          )
        ).to eq("SELECT add_continuous_aggregate_policy('activity_counts', start_offset => NULL, end_offset => NULL, schedule_interval => INTERVAL '1 hour', initial_start => '2023-02-08 20:00:00');")
      end
    end

    context 'when passing timezone' do
      it 'returns expected SQL' do
        expect(
          described_class.add_continuous_aggregate_policy_sql(
            'activity_counts',
            start_offset: nil,
            end_offset: nil,
            schedule_interval: '1 hour',
            timezone: "America/Montevideo"
          )
        ).to eq("SELECT add_continuous_aggregate_policy('activity_counts', start_offset => NULL, end_offset => NULL, schedule_interval => INTERVAL '1 hour', timezone => 'America/Montevideo');")
      end
    end
  end

  describe '.remove_continuous_aggregate_policy_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.remove_continuous_aggregate_policy_sql('activity_counts')
      ).to eq("SELECT remove_continuous_aggregate_policy('activity_counts');")
    end

    context 'when passing if_not_exists' do
      it 'returns expected SQL' do
        expect(
          described_class.remove_continuous_aggregate_policy_sql('activity_counts', if_not_exists: true)
        ).to eq("SELECT remove_continuous_aggregate_policy('activity_counts', if_not_exists => 'TRUE');")
      end
    end
  end
end
