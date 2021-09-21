RSpec.describe Timescale::HypertableHelpers do
  describe ".hypertable" do
    subject { Event.hypertable }
    it 'has compression enabled by default' do
      is_expected.to be_compression_enabled
    end

    its(:replication_factor) { is_expected.to be_nil }
    its(:data_nodes) { is_expected.to be_nil }
    its(:num_dimensions) { is_expected.to eq(1)}
    its(:tablespaces) { is_expected.to be_nil }
    its(:hypertable_name) { is_expected.to eq(Event.table_name) }
  end
end
