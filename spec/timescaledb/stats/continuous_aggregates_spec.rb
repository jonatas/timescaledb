RSpec.describe Timescaledb::Stats::ContinuousAggregates do
  subject(:stats) { described_class.new }

  describe '.to_h' do
    it 'returns expected structure' do
      expect(stats.to_h).to match(a_hash_including(total: a_kind_of(Integer)))
    end
  end
end