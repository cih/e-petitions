require "rails_helper"

RSpec.describe TrendingPetitionJournal, type: :model do
  it "has a valid factory" do
    expect(FactoryGirl.build(:trending_petition_journal)).to be_valid
  end

  describe "defaults" do
    (0..23).each do |hour|
      it "returns 0 for the hour_#{hour}_signature_count" do
        expect(subject.public_send("hour_#{hour}_signature_count")).to eq(0)
      end
    end
  end

  describe "indexes" do
    it { is_expected.to have_db_index(:petition_id) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:petition) }
    it { is_expected.to validate_presence_of(:date) }
  end

  describe ".for" do
    let(:petition) { FactoryGirl.create(:petition) }

    context "when there is a journal for the requested petition and date" do
      let(:date) { Date.current }
      let!(:existing_record) { FactoryGirl.create(:trending_petition_journal, petition: petition, created_at: date) }

      it "doesn't create a new record" do
        expect {
          described_class.for(petition, date)
        }.not_to change(described_class, :count)
      end

      it "fetches the instance from the DB" do
        fetched = described_class.for(petition, date)
        expect(fetched).to eq(existing_record)
      end
    end

    context "when there is no journal for the requested petition" do
      let!(:journal) { described_class.for(petition) }

      it "returns a newly created instance" do
        expect(journal).to be_an_instance_of(described_class)
      end

      it "persists the new instance in the DB" do
        expect(journal).to be_persisted
      end

      it "sets the petition of the new instance to the supplied petition" do
        expect(journal.petition).to eq(petition)
      end
    end
  end

  describe ".record_new_signature_for" do
    let(:petition) { FactoryGirl.create(:open_petition) }
    let(:time) { Time.parse("1 Jan 2017 13:05 UTC") }

    def journal
      described_class.for(petition)
    end

    around do |example|
      travel_to(time) { example.run }
    end

    context "when the supplied signature is valid" do
      let(:signature) { FactoryGirl.build(:validated_signature, petition: petition) }
      let(:now) { 1.hour.from_now.change(usec: 0) }

      it "increments the hour_13_signature_count by 1" do
        expect {
          described_class.record_new_signature_for(signature)
        }.to change { journal.hour_13_signature_count }.by(1)
      end

      it "updates the updated_at timestamp" do
        expect {
          described_class.record_new_signature_for(signature, now)
        }.to change { journal.updated_at }.to(now)
      end
    end

    context "when the supplied signature is nil" do
      let(:signature) { nil }

      it "does nothing" do
        expect {
          described_class.record_new_signature_for(signature)
        }.not_to change { journal.hour_13_signature_count }
      end
    end

    context "when the supplied signature has no petition" do
      let(:signature) { FactoryGirl.build(:validated_signature, petition: nil) }

      it "does nothing" do
        expect {
          described_class.record_new_signature_for(signature)
        }.not_to change { journal.hour_13_signature_count }
      end
    end

    context "when the supplied signature is not validated" do
      let(:signature) { FactoryGirl.build(:pending_signature, petition: petition) }

      it "does nothing" do
        expect {
          described_class.record_new_signature_for(signature)
        }.not_to change { journal.hour_13_signature_count }
      end
    end

    context "when no journal exists" do
      let(:signature) { FactoryGirl.build(:validated_signature, petition: petition) }

      it "creates a new journal" do
        expect {
          described_class.record_new_signature_for(signature)
        }.to change(described_class, :count).by(1)
      end
    end
  end

  describe ".invalidate_signature_for" do
    let!(:petition) { FactoryGirl.create(:open_petition) }
    let!(:journal) { FactoryGirl.create(:trending_petition_journal, petition: petition, hour_13_signature_count: signature_count, date: time.to_date) }
    let(:signature_count) { 1 }
    let(:time) { Time.parse("1 Jan 2017 13:05 UTC") }

    around do |example|
      travel_to(time) { example.run }
    end

    context "when the supplied signature is valid" do
      let(:signature) { FactoryGirl.build(:invalidated_signature, petition: petition) }
      let(:now) { 1.hour.from_now.change(usec: 0) }

      it "decrements the hour_13_signature_count by 1" do
        expect {
          described_class.invalidate_signature_for(signature)
        }.to change { journal.reload.hour_13_signature_count }.by(-1)
      end

      it "updates the updated_at timestamp" do
        expect {
          described_class.invalidate_signature_for(signature, now)
        }.to change { journal.reload.updated_at }.to(now)
      end
    end

    context "when the supplied signature is nil" do
      let(:signature) { nil }

      it "does nothing" do
        expect {
          described_class.invalidate_signature_for(signature)
        }.not_to change { journal.reload.hour_13_signature_count }
      end
    end

    context "when the supplied signature has no petition" do
      let(:signature) { FactoryGirl.build(:invalidated_signature, petition: nil) }

      it "does nothing" do
        expect {
          described_class.invalidate_signature_for(signature)
        }.not_to change { journal.reload.hour_13_signature_count }
      end
    end

    context "when the supplied signature is not validated" do
      let(:signature) { FactoryGirl.build(:pending_signature, petition: petition) }

      it "does nothing" do
        expect {
          described_class.invalidate_signature_for(signature)
        }.not_to change { journal.reload.hour_13_signature_count }
      end
    end

    context "when the signature count is already zero" do
      let(:signature) { FactoryGirl.build(:invalidated_signature, petition: petition) }
      let(:signature_count) { 0 }

      it "does nothing" do
        expect {
          described_class.invalidate_signature_for(signature)
        }.not_to change { journal.reload.hour_13_signature_count }
      end
    end

    context "when no journal exists" do
      let(:signature) { FactoryGirl.build(:invalidated_signature, petition: petition) }

      before do
        described_class.delete_all
      end

      it "creates a new journal" do
        expect {
          described_class.invalidate_signature_for(signature)
        }.to change(described_class, :count).by(1)
      end
    end
  end

  describe ".reset!" do
    let(:petition_1) { FactoryGirl.create(:petition) }
    let(:petition_2) { FactoryGirl.create(:petition) }
    let(:today) { Time.parse("1 Jan 2017 08:00") }
    let(:two_hours_ago) { today - 2.hours }
    let(:two_days_ago) { today - 2.days }

    around do |example|
      travel_to(today) { example.run }
    end

    before do
      described_class.for(petition_1).update_attribute(:hour_8_signature_count, 20)
      described_class.for(petition_2).update_attribute(:hour_8_signature_count, 100)
    end

    context "when there are no signatures" do
      it "resets all the hourly counts to 0 except for 1 for the creator signature" do
        described_class.reset!

        expect(described_class.for(petition_1).hour_8_signature_count).to eq 1
        expect(described_class.for(petition_2).hour_8_signature_count).to eq 1

        [*0..7, *9..23].each do |hour|
          expect(
            described_class.for(petition_1)
            .public_send("hour_#{hour}_signature_count")
          ).to eq 0

          expect(
            described_class.for(petition_2)
            .public_send("hour_#{hour}_signature_count")
          ).to eq 0
        end
      end
    end

    context "when there are signatures" do
      before do
        2.times { FactoryGirl.create(:validated_signature, petition: petition_1, validated_at: today) }
        2.times { FactoryGirl.create(:validated_signature, petition: petition_1, validated_at: two_hours_ago) }
        3.times { FactoryGirl.create(:validated_signature, petition: petition_1, validated_at: two_days_ago) }
        2.times { FactoryGirl.create(:pending_signature, petition: petition_1) }

        1.times { FactoryGirl.create(:validated_signature, petition: petition_2, validated_at: today) }
        1.times { FactoryGirl.create(:validated_signature, petition: petition_2, validated_at: two_hours_ago) }
        2.times { FactoryGirl.create(:validated_signature, petition: petition_2, validated_at: two_days_ago) }
        1.times { FactoryGirl.create(:pending_signature, petition: petition_2) }
      end

      it "resets the counts to that of the validated signatures for the petition, day and hour" do
        described_class.reset!

        expect(described_class.for(petition_1, today).hour_8_signature_count).to eq 3 # +1 for creator signature
        expect(described_class.for(petition_1, today).hour_6_signature_count).to eq 2
        expect(described_class.for(petition_1, two_days_ago).hour_8_signature_count).to eq 3

        expect(described_class.for(petition_2, today).hour_8_signature_count).to eq 2 # +1 for creator signature
        expect(described_class.for(petition_2, today).hour_6_signature_count).to eq 1
        expect(described_class.for(petition_2, two_days_ago).hour_8_signature_count).to eq 2
      end
    end
  end
end
