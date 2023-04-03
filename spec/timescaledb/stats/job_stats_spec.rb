RSpec.describe Timescaledb::Stats::JobStats do
  subject(:stats) { described_class.new }

  describe '.to_h' do
    it 'returns expected structure' do
      expect(stats.to_h).to match(
        a_hash_including(failures: a_kind_of(Integer), runs: a_kind_of(Integer), success: a_kind_of(Integer))
      )
    end
  end
end