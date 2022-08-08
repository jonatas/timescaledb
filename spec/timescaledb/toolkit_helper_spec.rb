
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

    before do
      yesterday = 1.day.ago
      [1,2,3].each_with_index do |v,i|
        model.create(device_id: 1, ts: yesterday + i.hour, val: v)
      end
    end

    describe "#volatility" do
      let(:plain_volatility_query) do
        model.select(<<~SQL).where("ts >= now()-'1 day'::interval").group("device_id")
        device_id, timevector(ts, val) -> sort() -> delta() -> abs() -> sum() as volatility
        SQL
      end

      it "works with plain sql"do
        expect(plain_volatility_query.first.volatility).to eq(1)
      end

      it { expect(model.value_column).to eq("val") }
      it { expect(model.time_column).to eq(:ts) }

      context "with columns specified in the volatility scope" do
        let(:query) do
          model
            .where("ts >= now()-'1 day'::interval")
            .volatility("device_id")
        end
        it "segment by the param in the volatility"do
          expect(query.to_sql).to eq(plain_volatility_query.to_sql.tr("\n", ""))
        end
      end

      context "without columns" do
        let(:query) do
          model
            .where("ts >= now()-'1 day'::interval")
            .volatility
        end
        it "uses the default segment_by_column"do
          expect(query.to_sql).to eq(plain_volatility_query.to_sql.tr("\n", ""))
        end
      end

      context "several devices" do
        before :each do
          yesterday = 1.day.ago
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
          model
            .where("ts >= now()-'1 day'::interval")
            .volatility(nil) # will not segment by.
        end
        let(:volatility_query_for_every_device) do
          model
            .where("ts >= now()-'1 day'::interval")
            .order("device_id")
            .volatility("device_id")
        end

        specify do
          expect(volatility_query_for_all.map(&:attributes)).to eq([
            {"device_id"=>nil, "volatility"=>8.0}])

          expect(volatility_query_for_every_device.map(&:attributes)).to eq([
            {"device_id"=>1, "volatility"=>1.0},
            {"device_id"=>2, "volatility"=>2.0},
            {"device_id"=>3, "volatility"=>3.0}])
        end
      end
    end
  end
=begin
    describe "#time_weight" do
      specify do
        require "pry";binding.pry 
    #SELECT hyperloglog(device_id) -> distinct_count() FROM measurements;
      end
    end
  end
=end
end
