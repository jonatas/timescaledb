RSpec.describe Timescaledb::SchemaDumper, database_cleaner_strategy: :truncation do
  let(:con) { ActiveRecord::Base.connection }

  let(:query) do
    Event.select("time_bucket('1m', created_at) as time,
                  identifier as label,
                  count(*) as value").group("1,2")
  end

  context "hypertables" do
    let(:sorted_hypertables) do
      %w[events hypertable_with_custom_time_column hypertable_with_no_options
      hypertable_with_options measurements migration_tests]
    end

    it "dump the create_table sorted by hypertable_name" do
      previous = 0
      sorted_hypertables.each do |name|
        index = output.index(%|create_hypertable "#{name}"|)
        expect(index).to be > previous
        previous = index
      end
    end

    context "with retention policies" do
      before do
        con.create_retention_policy("events", interval: "1 week")
      end
      after do
        con.remove_retention_policy("events")
      end

      it "add retention policies after hypertables" do
        last_hypertable = output.index(%|create_hypertable "#{sorted_hypertables.last}"|)
        index = output.index(%|create_retention_policy "events", interval: "P7D"|)
        expect(index).to be > last_hypertable
      end
    end
  end

  let(:output) do
    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(con, stream)
    stream.string
  end

  it "dumps a create_continuous_aggregate for a view in the database" do
    con.execute("DROP MATERIALIZED VIEW IF EXISTS event_counts")
    con.create_continuous_aggregate(:event_counts, query)

    if defined?(Scenic)
      Scenic.load # Normally this happens in a railtie, but we aren't loading a full rails env here
      con.execute("DROP VIEW IF EXISTS searches")
      con.create_view :searches, sql_definition: "SELECT 'needle'::text AS haystack"
    end


    expect(output).to include 'create_continuous_aggregate("event_counts"'
    expect(output).not_to include 'create_view "event_counts"' # Verify Scenic ignored this view
    expect(output).to include 'create_view "searches", sql_definition: <<-SQL' if defined?(Scenic)
  end
end
