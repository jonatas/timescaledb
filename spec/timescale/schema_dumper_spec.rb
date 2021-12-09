RSpec.describe Timescale::SchemaDumper, database_cleaner_strategy: :truncation do
  let(:con) { ActiveRecord::Base.connection }

  let(:query) do
    Event.select("time_bucket('1m', created_at) as time,
                  identifier as label,
                  count(*) as value").group("1,2")
  end

  it "dumps a create_continuous_aggregate for a view in the database" do
    con.execute("DROP MATERIALIZED VIEW IF EXISTS event_counts")
    con.create_continuous_aggregate(:event_counts, query)

    if defined?(Scenic)
      Scenic.load # Normally this happens in a railtie, but we aren't loading a full rails env here
      con.execute("DROP VIEW IF EXISTS searches")
      con.create_view :searches, sql_definition: "SELECT 'needle'::text AS haystack"
    end

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(con, stream)
    output = stream.string

    expect(output).to include 'create_continuous_aggregate("event_counts"'
    expect(output).not_to include 'create_view "event_counts"' # Verify Scenic ignored this view
    expect(output).to include 'create_view "searches", sql_definition: <<-SQL' if defined?(Scenic)
  end
end
