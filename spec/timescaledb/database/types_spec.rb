# frozen_string_literal: true

require 'spec_helper'

require 'timescaledb/database'

RSpec.describe Timescaledb::Database do
  describe '.interval_to_sql' do
    context 'when passing nil' do
      it 'returns NULL' do
        expect(described_class.interval_to_sql(nil)).to eq('NULL')
      end
    end

    context 'when passing an integer' do
      it 'returns raw integer value' do
        expect(described_class.interval_to_sql(60*60*24)).to eq(86400)
      end
    end

    context 'when passing a string' do
      it 'returns the interval SQL statement' do
        expect(described_class.interval_to_sql('1 day')).to eq("INTERVAL '1 day'")
      end
    end
  end

  describe '.boolean_to_sql' do
    context 'when passing true' do
      it 'returns expected SQL value' do
        expect(described_class.boolean_to_sql(true)).to eq("'TRUE'")
      end
    end

    context 'when passing false' do
      it 'returns expected SQL value' do
        expect(described_class.boolean_to_sql(false)).to eq("'FALSE'")
      end
    end

    context 'when passing nil' do
      it 'returns expected SQL value' do
        expect(described_class.boolean_to_sql(nil)).to eq("'FALSE'")
      end
    end
  end
end
