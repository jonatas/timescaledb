RSpec.describe Timescale::MigrationHelpers do
  describe ".create_table" do
    let(:con) { ActiveRecord::Base.connection }

    before(:each) do
      if con.table_exists?(:migration_tests)
        con.drop_table :migration_tests
      end
    end

    subject(:create_table) do
      p hypertable_options
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
        compression_interval: '7 days'
      }
    end

    it 'call setup_hypertable_options with params' do
      expect(ActiveRecord::Base.connection).to receive(:setup_hypertable_options).with(:migration_tests, hypertable_options).once
      create_table
    end

    context 'with hypertable options' do
      let(:hypertable) do
        Timescale::Hypertable.find_by(hypertable_name: :migration_tests)
      end

      it 'enables compression' do
        create_table
        expect(hypertable.attributes).to include({
          "compression_enabled"=>true,
          "data_nodes"=>nil,
          "hypertable_name"=>"migration_tests",
          "hypertable_schema" => "public",
          "is_distributed" => false,
          "num_chunks" => 0,
          "num_dimensions" => 1,
          "replication_factor" => nil,
          "tablespaces" => nil})
      end
    end
  end
end
