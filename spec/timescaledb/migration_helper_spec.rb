RSpec.describe Timescaledb::MigrationHelpers, database_cleaner_strategy: :truncation do

  describe ".drop_table" do
    before(:all) do
      # make sure to drop the table before testing so that we can test
      ActiveRecord::Base.connection.drop_table(:migration_tests, if_exists: true, force: :cascade)
    end

    let(:con) { ActiveRecord::Base.connection }

    subject(:drop_table) do
      con.drop_table :migration_tests, if_exists: true, force: :cascade
    end

    let(:hypertable_options) do
      {
        time_column: 'created_at',
        chunk_time_interval: '1 min',
        compress_segmentby: 'identifier',
        compress_orderby: 'created_at',
        compress_after: '7 days'
      }
    end

    it 'drops table as normal' do
      con.create_table :migration_tests, hypertable: hypertable_options, id: false do |t|
        t.string :identifier
        t.jsonb :payload
        t.timestamps
      end

      expect(Timescaledb::Hypertable.find_by(hypertable_name: :migration_tests)).not_to be_nil
      expect(con.table_exists?(:migration_tests)).to be true

      drop_table

      expect(Timescaledb::Hypertable.find_by(hypertable_name: :migration_tests)).to be_nil
      expect(con.table_exists?(:migration_tests)).to be false
    end

    context 'when there are dependent continuous aggregates' do

        let(:model_with_nested_caggs) do
          MigrationTests = Class.new(ActiveRecord::Base) do
            self.table_name = 'migration_tests'
            acts_as_hypertable
          end
        end

        let(:create_table_with_nested_caggs) do
          con.create_table :migration_tests, hypertable: hypertable_options, id: false do |t|
            t.string :identifier
            t.jsonb :payload
            t.timestamps
          end

          query = model_with_nested_caggs.select("time_bucket('1 minute', created_at) as bucket_1_min, identifier, COUNT(*) as count")
                                         .group("identifier, bucket_1_min")

          cagg_options = {
            with_data: false,
            refresh_policies: {
              start_offset: "INTERVAL '30 days'", end_offset: "INTERVAL '1 minute'",
              schedule_interval: "INTERVAL '1 minute'"
            }
          }

          con.create_continuous_aggregate('migration_cagg', query, **cagg_options)

          # second cagg is simply nested on top of the first cagg with a larger time bucket.
          query = <<~SQL
            SELECT time_bucket('1 hour', bucket_1_min) as bucket_1_hour, identifier, COUNT(*) as count
            FROM migration_cagg
            GROUP BY identifier, bucket_1_hour
          SQL
          con.create_continuous_aggregates 'migration_cagg_2', query, with_data: true
        end

        # Create table with nested caggs
        before(:each) do
          create_table_with_nested_caggs
        end

        before(:each) do
          allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original
        end

        it 'drops dependent continuous aggregates' do
          # confirm we actually generated the expected sql
          expect(ActiveRecord::Base.connection)
            .to receive(:execute)
                  .with(/DROP MATERIALIZED VIEW IF EXISTS "migration_cagg" CASCADE/)
                  .once

          # confirm both table and caggs exist before testing
          expect(Timescaledb::Hypertable.find_by(hypertable_name: :migration_tests)).not_to be_nil
          expect(con.table_exists?(:migration_tests)).to be true

          expect(con.execute("SELECT to_regclass('migration_cagg')").first['to_regclass']).not_to be_nil
          expect(con.execute("SELECT to_regclass('migration_cagg_2')").first['to_regclass']).not_to be_nil

          drop_table

          expect(Timescaledb::Hypertable.find_by(hypertable_name: :migration_tests)).to be_nil
          expect(con.table_exists?(:migration_tests)).to be false

          expect(con.execute("SELECT to_regclass('migration_cagg')").first['to_regclass']).to be_nil
          expect(con.execute("SELECT to_regclass('migration_cagg_2')").first['to_regclass']).to be_nil
        end
      end

  end

  describe ".create_table" do
    let(:con) { ActiveRecord::Base.connection }

    before(:each) do
      con.drop_table :migration_tests, if_exists: true, force: :cascade
    end

    subject(:create_table) do
      con.create_table :migration_tests, hypertable: hypertable_options, id: false do |t|
        t.string :identifier
        t.jsonb :payload
        t.timestamps
      end
    end

    let(:hypertable_options) do
      {
        time_column: 'created_at',
        chunk_time_interval: '1 min',
        compress_segmentby: 'identifier',
        compress_orderby: 'created_at',
        compress_after: '7 days'
      }
    end

    it 'call create_hypertable with params' do
      expect(ActiveRecord::Base.connection)
        .to receive(:create_hypertable)
        .with(:migration_tests, hypertable_options)
        .once

      create_table
    end

    context 'with hypertable options' do
      let(:hypertable) do
        Timescaledb::Hypertable.find_by(hypertable_name: :migration_tests)
      end

      it 'enables compression' do
        create_table

        expect(hypertable.attributes).to include({
          "compression_enabled"=>true,
          "hypertable_name"=>"migration_tests",
          "hypertable_schema" => "public",
          "num_chunks" => 0,
          "num_dimensions" => 1,
          "tablespaces" => nil})
      end
    end

    context 'with force: cascade' do
      context 'when there are dependent continuous aggregates' do

        let(:model_with_nested_caggs) do
          MigrationTests = Class.new(ActiveRecord::Base) do
            self.table_name = 'migration_tests'
            acts_as_hypertable
          end
        end

        let(:create_table_with_nested_caggs) do
          con.create_table :migration_tests, hypertable: hypertable_options, id: false do |t|
            t.string :identifier
            t.jsonb :payload
            t.timestamps
          end

          query = model_with_nested_caggs.select("time_bucket('1 minute', created_at) as bucket_1_min, identifier, COUNT(*) as count")
                                         .group("identifier, bucket_1_min")

          cagg_options = {
            with_data: false,
            refresh_policies: {
              start_offset: "INTERVAL '30 days'", end_offset: "INTERVAL '1 minute'",
              schedule_interval: "INTERVAL '1 minute'"
            }
          }

          con.create_continuous_aggregate('migration_cagg', query, **cagg_options)

          # second cagg is simply nested on top of the first cagg with a larger time bucket.
          query = <<~SQL
            SELECT time_bucket('1 hour', bucket_1_min) as bucket_1_hour, identifier, COUNT(*) as count
            FROM migration_cagg
            GROUP BY identifier, bucket_1_hour
          SQL
          con.create_continuous_aggregates 'migration_cagg_2', query, with_data: true
        end

        # Create table with nested caggs
        before(:each) do
          create_table_with_nested_caggs
        end

        before(:each) do
          allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original
        end

        it 'drops dependent continuous aggregates' do
          # confirm we actually generated the expected sql
          expect(ActiveRecord::Base.connection)
            .to receive(:execute)
            .with(/DROP MATERIALIZED VIEW IF EXISTS "migration_cagg" CASCADE/)
            .once

          # make sure that any new create_table with force: :cascade does not raise an exception due to dependent objects
          expect {
            con.create_table :migration_tests, force: :cascade, hypertable: hypertable_options, id: false do |t|
              t.string :identifier
              t.jsonb :payload
              t.timestamps
            end
          }.not_to raise_exception

          # expect the table still exists
          expect(Timescaledb::Hypertable.find_by(hypertable_name: :migration_tests)).not_to be_nil

        end
      end
    end
  end

  describe ".create_caggs" do
    let(:con) { ActiveRecord::Base.connection }

    before(:each) do
      con.drop_table :ticks, if_exists: true, force: :cascade
      con.create_table :ticks, hypertable: hypertable_options, id: false do |t|
        t.string :symbol
        t.decimal :price
        t.integer :volume
        t.timestamps
      end
    end

    after(:each) do
      con.drop_continuous_aggregates(:ohlc_1m)
    end

    let(:hypertable_options) do
      {
        time_column: 'created_at',
        chunk_time_interval: '1 min',
        compress_segmentby: 'symbol',
        compress_orderby: 'created_at',
        compress_after: '7 days'
      }
    end

    let(:model) do
      Tick = Class.new(ActiveRecord::Base) do
        self.table_name = 'ticks'
        self.primary_key = 'symbol'

        acts_as_hypertable
      end
    end

    let(:query) do
      model.select("time_bucket('1m', created_at) as time,
          symbol,
          FIRST(price, created_at) as open,
          MAX(price) as high,
          MIN(price) as low,
          LAST(price, created_at) as close,
          SUM(volume) as volume").group("1,2")
    end
    let(:options) do
      {with_data: true}
    end

    subject(:create_caggs) { con.create_continuous_aggregates('ohlc_1m', query, **options) }

    specify do
      expect do
        create_caggs
      end.to change { model.caggs.count }.from(0).to(1)

      expect(model.caggs.first.jobs).to be_empty
    end

    context 'when using refresh policies' do
      let(:options) do
        {
          with_data: false,
          refresh_policies: {
            start_offset: "INTERVAL '1 month'",
            end_offset: "INTERVAL '1 minute'",
            schedule_interval: "INTERVAL '1 minute'"
          }
        }
      end

      specify do
        expect do
          create_caggs
        end.to change { model.caggs.count }.from(0).to(1)

        expect(model.caggs.first.jobs).not_to be_empty
      end
    end

    context 'when overriding WITH clauses' do
      let(:options) do
        {
          materialized_only: true,
          create_group_indexes: true
        }
      end

      before do
        allow(ActiveRecord::Base.connection).to(receive(:execute).and_call_original)
      end

      specify do
        expect do
          create_caggs
        end.to change { model.caggs.count }.from(0).to(1)
      end

      context 'when overriding WITH clause timescaledb.materialized_only' do
        let(:options) do
          {
            materialized_only: true
          }
        end

        specify do
          create_caggs
          expect(ActiveRecord::Base.connection).to have_received(:execute).with(include('timescaledb.materialized_only=true'))
        end
      end

      context 'when overriding WITH clause timescaledb.create_group_indexes' do
        let(:options) do
          {
            create_group_indexes: true
          }
        end

        specify do
          create_caggs
          expect(ActiveRecord::Base.connection).to have_received(:execute).with(include('timescaledb.create_group_indexes=true'))
        end
      end

      context 'when overriding WITH clause timescaledb.finalized' do
        # finalized: true is no longer output (deprecated in TimescaleDB 2.14+)
        # Only finalized: false is output for legacy compatibility with 2.7-2.13
        let(:options) do
          {
            finalized: false
          }
        end

        specify do
          skip "TimescaleDB 2.14+ no longer supports partial (non-finalized) continuous aggregates" if Gem::Version.new(Timescaledb.extension.version) >= Gem::Version.new("2.14")

          create_caggs
          expect(ActiveRecord::Base.connection).to have_received(:execute).with(include('timescaledb.finalized=false'))
        end
      end

      context 'when finalized: true (default)' do
        let(:options) do
          {
            finalized: true
          }
        end

        specify 'does not include finalized parameter' do
          create_caggs
          expect(ActiveRecord::Base.connection).not_to have_received(:execute).with(include('timescaledb.finalized'))
        end
      end
    end
  end
end
