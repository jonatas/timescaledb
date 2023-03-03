# frozen_string_literal: true

require 'spec_helper'

require 'timescaledb/database'

RSpec.describe Timescaledb::Database do
  describe '.hypertable_size_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.hypertable_size_sql('events')
      ).to eq("SELECT hypertable_size('events');")
    end
  end

  describe '.hypertable_detailed_size_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.hypertable_detailed_size_sql('events')
      ).to eq("SELECT * FROM hypertable_detailed_size('events');")
    end
  end

  describe '.hypertable_index_size_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.hypertable_index_size_sql('second_index')
      ).to eq("SELECT hypertable_index_size('second_index');")
    end
  end

  describe '.chunks_detailed_size_sql' do
    it 'returns expected SQL' do
      expect(
        described_class.chunks_detailed_size_sql('events')
      ).to eq("SELECT * FROM chunks_detailed_size('events');")
    end
  end
end
