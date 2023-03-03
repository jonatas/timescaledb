module Timescaledb
  class Database
    module ChunkStatements
      # @see https://docs.timescale.com/api/latest/compression/compress_chunk/
      #
      # @param [String] chunk_name The name of the chunk to be compressed
      # @return [String] The compress_chunk SQL statement
      def compress_chunk_sql(chunk_name)
        "SELECT compress_chunk(#{quote(chunk_name)});"
      end

      # @see https://docs.timescale.com/api/latest/compression/decompress_chunk/
      #
      # @param [String] chunk_name The name of the chunk to be decompressed
      # @return [String] The decompress_chunk SQL statement
      def decompress_chunk_sql(chunk_name)
        "SELECT decompress_chunk(#{quote(chunk_name)});"
      end
    end
  end
end
