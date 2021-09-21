RSpec.describe Timescale do
  it "has a version number" do
    expect(Timescale::VERSION).not_to be nil
  end

  describe ".chunks" do
    subject { Timescale.chunks }

    context "when no data is inserted" do
      it { is_expected.to be_empty }
    end

    context "when data is added" do
      before do
        Event.create identifier: "sign_up", payload: {"name" => "Eon"}
      end

      it { is_expected.not_to be_empty }
      it { expect(Event.chunks).not_to be_empty }
      it { expect(subject.first.hypertable_name).to eq('events') }
      it { expect(subject.first.attributes).to eq(Event.chunks.first.attributes) }
    end
  end

  describe ".hypertables" do
    subject { Timescale.hypertables }

    context "with default example from main setup" do
      it { is_expected.not_to be_empty }
      specify do
        expect(subject.first.attributes)
          .to eq(Event.hypertable.attributes)
      end
    end
  end
end
