module Timescaledb
  class Chunk < ActiveRecord::Base
    self.table_name = "timescaledb_information.chunks"
    self.primary_key = "chunk_name"

    belongs_to :hypertable, foreign_key: :hypertable_name

    scope :compressed, -> { where(is_compressed: true) }
    scope :uncompressed, -> { where(is_compressed: false) }

    scope :resume, -> do
      {
        total: count,
        compressed: compressed.count,
        uncompressed: uncompressed.count
      }
    end

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
