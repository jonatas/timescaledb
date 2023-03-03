# frozen_string_literal: true

require 'spec_helper'

require 'timescaledb/database'

RSpec.describe Timescaledb::Database do
  describe '.compress_chunk_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.compress_chunk_sql('_timescaledb_internal._hyper_1_2_chunk')
      ).to eq("SELECT compress_chunk('_timescaledb_internal._hyper_1_2_chunk');")
    end
  end

  describe '.decompress_chunk_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.decompress_chunk_sql('_timescaledb_internal._hyper_1_2_chunk')
      ).to eq("SELECT decompress_chunk('_timescaledb_internal._hyper_1_2_chunk');")
    end
  end
end
