RSpec.describe Timescale::ActsAsHypertable do
  describe ".hypertable_options" do
    context "when non-default options are set" do
      let(:model) { HypertableWithCustomTimeColumn }

      it "uses the non-default options" do
        aggregate_failures do
          expect(model.hypertable_options).not_to eq(Timescale.default_hypertable_options)
          expect(model.hypertable_options[:time_column]).to eq(:timestamp)
        end
      end
    end

    context "when no options are set" do
      let(:model) { HypertableWithNoOptions }

      it "uses the default options" do
        expect(model.hypertable_options).to eq(Timescale.default_hypertable_options)
      end
    end
  end

  describe ".hypertable" do
    subject { Event.hypertable }

    it 'has compression enabled by default' do
      is_expected.to be_compression_enabled
    end

    its(:replication_factor) { is_expected.to be_nil }
    its(:data_nodes) { is_expected.to be_nil }
    its(:num_dimensions) { is_expected.to eq(1) }
    its(:tablespaces) { is_expected.to be_nil }
    its(:hypertable_name) { is_expected.to eq(Event.table_name) }
  end
end
