# frozen_string_literal: true

require 'spec_helper'

require 'timescaledb/database'

RSpec.describe Timescaledb::Database do
  describe '.quote' do
    it 'wraps given text between single quotes' do
      expect(described_class.quote('events')).to eq("'events'")
    end

    context 'when including single quotes' do
      it 'escapes those characters' do
        expect(described_class.quote("event's")).to eq("'event''s'")
      end
    end

    context 'when including backslashes' do
      it 'escapes those characters' do
        expect(described_class.quote("ev\\ents")).to eq("'ev\\\\ents'")
      end
    end

    context 'when including a mix of single quote and backslash characters' do
      it 'escapes all characters' do
        expect(described_class.quote("ev\\ent's")).to eq("'ev\\\\ent''s'")
      end
    end
  end
end
