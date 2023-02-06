require_relative 'database/quoting'
require_relative 'database/schema_statements'
require_relative 'database/types'

module Timescaledb
  class Database
    extend Quoting
    extend SchemaStatements
    extend Types
  end
end
