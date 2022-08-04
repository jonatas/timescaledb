
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
    end
  end
end
