require "bundler/setup"
require "pry"
require "rspec/its"
require "timescale"
require "dotenv"

Dotenv.load!

ActiveRecord::Base.establish_connection(ENV['PG_URI_TEST'])

def create_hypertable(table_name:, time_column_name: :created_at, options: {})
  create_table(table_name.to_sym, id: false, hypertable: options) do |t|
    t.string :identifier, null: false
    t.jsonb :payload
    t.timestamp time_column_name.to_sym
  end
end

def setup_tables
  ActiveRecord::Schema.define(version: 1) do
    create_hypertable(
      table_name: :events,
      time_column_name: :created_at,
      options: {
        time_column: 'created_at',
        chunk_time_interval: '1 min',
        compress_segmentby: 'identifier',
        compression_interval: '7 days'
      }
    )

    create_hypertable(table_name: :hypertable_with_no_options)

    create_hypertable(
      table_name: :hypertable_with_options,
      time_column_name: :timestamp,
      options: {
        time_column: 'timestamp',
        chunk_time_interval: '1 min',
        compress_segmentby: 'identifier',
        compress_orderby: 'timestamp',
        compression_interval: '7 days'
      }
    )

    create_hypertable(
      table_name: :hypertable_with_custom_time_column,
      time_column_name: :timestamp,
      options: { time_column: 'timestamp' }
    )
  end
end

def teardown_tables
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table, force: :cascade)
  end
end

def destroy_all_chunks_for!(klass)
  sql = <<-SQL
    SELECT drop_chunks('#{klass.table_name}', '#{1.week.from_now}'::date)
  SQL

  ActiveRecord::Base.connection.execute(sql)
end

class Event < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable
end

class HypertableWithNoOptions < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable
end

class HypertableWithOptions < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable time_column: :timestamp
end

class HypertableWithCustomTimeColumn < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable time_column: :timestamp
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
    teardown_tables
    setup_tables
  end
end
