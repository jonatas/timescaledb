RSpec.describe Timescaledb do
  it "has a version number" do
    expect(Timescaledb::VERSION).not_to be nil
  end

  describe ".chunks" do
    subject { Timescaledb.chunks }

    context "when no data is inserted" do
      it { is_expected.to be_empty }
    end

    context "when data is added" do
      before do
        Event.create identifier: "sign_up", payload: {"name" => "Eon"}
      end

      after do
        destroy_all_chunks_for!(Event)
      end

      it { is_expected.not_to be_empty }
      it { expect(Event.chunks).not_to be_empty }
      it { expect(subject.first.hypertable_name).to eq('events') }
      it { expect(subject.first.attributes).to eq(Event.chunks.first.attributes) }
    end
  end

  describe ".hypertables" do
    subject { Timescaledb.hypertables }

    context "with default example from main setup" do
      it { is_expected.not_to be_empty }
      specify do
        expect(subject.first.attributes)
          .to eq(Event.hypertable.attributes)
      end
    end
  end

  describe ".default_hypertable_options" do
    subject { Timescaledb.default_hypertable_options }

    it { is_expected.to eq(Timescaledb::ActsAsHypertable::DEFAULT_OPTIONS) }
  end
end
