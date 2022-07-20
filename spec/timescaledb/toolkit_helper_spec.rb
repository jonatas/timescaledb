
RSpec.describe Timescaledb::ToolkitHelpers, database_cleaner_strategy: :truncation do
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
      end
    end

    let(:query) do
      model.select(<<~SQL).where("ts >= now()-'1 day'::interval").group("device_id").first
        device_id, timevector(ts, val) -> sort() -> delta() -> abs() -> sum() as volatility
      SQL
    end

    before do
      yesterday = 1.day.ago
      [1,2,3].each_with_index do |v,i|
        model.create(device_id: 1, ts: yesterday + i.hour, val: v)
      end
    end

    specify do
      expect(query.volatility).to eq(1)
    end
  end
end
