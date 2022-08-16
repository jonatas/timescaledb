
RSpec.describe Timescaledb::Toolkit::Helpers, database_cleaner_strategy: :truncation do
  let(:con) { ActiveRecord::Base.connection }


  let(:hypertable_options) do
    {
      time_column: 'ts',
      chunk_time_interval: '1 day',
      compress_segmentby: 'device_id',
      compress_orderby: 'ts',
      compression_interval: '7 days'
    }
  end

  describe "add_toolkit_to_search_path!" do
    it "adds toolkit_experimental to search path" do
      expect do
        con.add_toolkit_to_search_path!
      end.to change(con, :schema_search_path)
        .from('"$user", public')
        .to('toolkit_experimental, "$user", public')
    end
  end

  describe "pipeline functions" do
    before(:each) do
      con.add_toolkit_to_search_path!
      if con.table_exists?(:measurements)
        con.drop_table :measurements, force: :cascade
      end
      con.create_table :measurements, hypertable: hypertable_options, id: false do |t|
        t.integer :device_id
        t.decimal :val
        t.timestamp :ts
      end
    end

    let(:model) do
      Measurement = Class.new(ActiveRecord::Base) do
        self.table_name = 'measurements'
        self.primary_key = 'device_id'

        acts_as_hypertable time_column: "ts"

        acts_as_time_vector segment_by: "device_id",
          value_column: "val",
          time_column: "ts"
      end
    end

    let(:yesterday) { 1.day.ago }

    before do
      [1,2,3].each_with_index do |v,i|
        model.create(device_id: 1, ts: yesterday + i.hour, val: v)
      end
    end

    describe "#volatility" do
      let(:plain_volatility_query) do
        model.select(<<~SQL).group("device_id")
        device_id, timevector(ts, val) -> sort() -> delta() -> abs() -> sum() as volatility
        SQL
      end

      it "works with plain sql"do
        expect(plain_volatility_query.first.volatility).to eq(2)
      end

      it { expect(model.value_column).to eq("val") }
      it { expect(model.time_column).to eq(:ts) }

      context "with columns specified in the volatility scope" do
        let(:query) do
          model.volatility("device_id")
        end
        it "segment by the param in the volatility"do
          expect(query.to_sql).to eq(plain_volatility_query.to_sql.tr("\n", ""))
        end
      end

      context "without columns" do
        let(:query) do
          model.volatility
        end
        it "uses the default segment_by_column"do
          expect(query.to_sql).to eq(plain_volatility_query.to_sql.tr("\n", ""))
        end
      end

      context "benchmarking" do
        specify do
          
          require "pry";binding.pry 

        end
      end

      context "several devices" do
        before :each do
          [1,2,3].each_with_index do |v,i|
            model.create(device_id: 2, ts: yesterday + i.hour, val: v+i)
            model.create(device_id: 3, ts: yesterday + i.hour, val: i * i)
          end
        end

        # Dataset example now
        ##  model.all.order(:device_id, :ts).map(&:attributes)
        #=> [
        #     {"device_id"=>1, "val"=>1.0, "ts"=>...},
        #     {"device_id"=>1, "val"=>2.0, "ts"=>...},
        #     {"device_id"=>1, "val"=>3.0, "ts"=>...},
        #     {"device_id"=>2, "val"=>1.0, "ts"=>...},
        #     {"device_id"=>2, "val"=>3.0, "ts"=>...},
        #     {"device_id"=>2, "val"=>5.0, "ts"=>...},
        #     {"device_id"=>3, "val"=>0.0, "ts"=>...},
        #     {"device_id"=>3, "val"=>1.0, "ts"=>...},
        #     {"device_id"=>3, "val"=>4.0, "ts"=>...}]

        let(:volatility_query_for_all) do
          model.volatility(nil) # will not segment by.
        end
        let(:volatility_query_for_every_device) do
          model.order("device_id")
            .volatility("device_id")
        end

        specify do
          expect(volatility_query_for_all.map(&:attributes)).to eq([
            {"device_id"=>nil, "volatility"=>11.0}])

          expect(volatility_query_for_every_device.map(&:attributes)).to eq([
            {"device_id"=>1, "volatility"=>2.0},
            {"device_id"=>2, "volatility"=>4.0},
            {"device_id"=>3, "volatility"=>4.0}])
        end
      end
    end
    describe "interpolate and backfill" do
      before do
         model.create(device_id: 1, ts: yesterday + 4.hour, val: 5)
         model.create(device_id: 1, ts: yesterday + 6.hour, val: 7)
         model.create(device_id: 1, ts: yesterday + 8.hour, val: 9)
      end
      specify do
        res = model.select(<<SQL).group("hour, device_id").order("hour")
          time_bucket_gapfill('1 hour', ts,
             now() - INTERVAL '24 hours',
             now() - INTERVAL '16 hours') AS hour,
          device_id,
          avg(val) AS value,
          interpolate(avg(val))
SQL

        expect(res.map{|e|[e["value"]&.to_f,e["interpolate"]]}).to eq([
          [1.0, 1.0],
          [2.0, 2.0],
          [3.0, 3.0],
          [nil, 4.0],
          [5.0, 5.0],
          [nil, 6.0],
          [7.0, 7.0],
          [nil, 8.0],
          [9.0, 9.0]])
      end
    end
    describe "stats_aggs" do
      let(:query) do
        model.select(<<~SQL).group(1)
          time_bucket('1 h'::interval, ts) as bucket,
          stats_agg(val) as stats
        SQL
      end
      let(:options) { { with_data: true } }
      before(:each) { con.create_continuous_aggregates('measurements_stats_1h', query, **options) }
      after(:each) { con.drop_continuous_aggregates('measurements_stats_1m') rescue nil }
      let(:view) do
        con.execute(<<~SQL)
        SELECT
        bucket,
          average(rolling(stats) OVER (ORDER BY bucket RANGE '#{preceeding_range}' PRECEDING)),
          stddev(rolling(stats) OVER (ORDER BY bucket RANGE '#{preceeding_range}' PRECEDING))
        FROM measurements_stats_1h;
        SQL
      end

      context 'when one hour preceeding' do
        let(:preceeding_range) { '1 hour' }
        specify do
          expect(view.map{|e|e["average"]}).to eq([1,1.5,2.5])
        end
      end

      context 'when two hour preceeding' do
        let(:preceeding_range) { '2 hours' }
        specify do
          expect(view.map{|e|e["average"]}).to eq([1,1.5,2.0])
        end
      end
    end
  end
end
