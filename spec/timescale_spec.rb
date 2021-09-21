RSpec.describe Timescale do
  it "has a version number" do
    expect(Timescale::VERSION).not_to be nil
  end
  before :all do
    ActiveRecord::Base.establish_connection(ENV['PG_URI'])

    # Simple example
    class Event < ActiveRecord::Base
      self.primary_key = "identifier"

      include Timescale::HypertableHelpers
    end

    ActiveRecord::Base.connection.instance_exec do
      ActiveRecord::Base.logger = Logger.new(STDOUT)

      drop_table(:events) if Event.table_exists?

      hypertable_options = {
        time_column: 'created_at',
        chunk_time_interval: '1 min',
        compress_segmentby: 'identifier',
        compression_interval: '7 days'
      }

      create_table(:events, id: false, hypertable: hypertable_options) do |t|
        t.string :identifier, null: false
        t.jsonb :payload
        t.timestamps
      end
    end
  end
end
