RSpec.describe Timescaledb::Stats::Chunks do
  let(:hypertables) { Timescaledb.connection.query('SELECT * FROM timescaledb_information.hypertables') }

  subject(:stats) { described_class.new(hypertables) }

  describe '.to_h' do
    it 'returns expected structure' do
      expect(stats.to_h).to match(
        a_hash_including(compressed: a_kind_of(Integer), total: a_kind_of(Integer), uncompressed: a_kind_of(Integer))
      )
    end
  end
end