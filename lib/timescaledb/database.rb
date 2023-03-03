require_relative 'database/chunk_statements'
require_relative 'database/hypertable_statements'
require_relative 'database/quoting'
require_relative 'database/schema_statements'
require_relative 'database/types'

module Timescaledb
  class Database
    extend ChunkStatements
    extend HypertableStatements
    extend Quoting
    extend SchemaStatements
    extend Types
  end
end
