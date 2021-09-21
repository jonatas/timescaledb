
module Timescale
  class Chunk < ActiveRecord::Base
    self.table_name = "timescaledb_information.chunks"

    def compress!
      execute("SELECT compress_chunk(#{chunk_relation})")
    end

    def decompress!
      execute("SELECT decompress_chunk(#{chunk_relation})")
    end

    def chunk_relation
      "('#{chunk_schema}.#{chunk_name}')::regclass"
    end

    def execute(sql)
      self.class.connection.execute(sql)
    end
  end
end
