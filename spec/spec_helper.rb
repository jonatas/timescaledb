require "bundler/setup"
require 'rspec/its'
require "timescale"
require 'dotenv'

Dotenv.load!

ActiveRecord::Base.establish_connection(ENV['PG_URI_TEST'])

class Event < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable time_column: :created_at

  def self.destroy_all_chunks!
    sql = <<-SQL
      SELECT drop_chunks('#{table_name}', '#{Date.tomorrow}'::date)
    SQL

    connection.execute(sql)
  end
end

def create_events_table!
  ActiveRecord::Base.connection.instance_exec do
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

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
  end

  config.before :suite do
    create_events_table!
  end
end
