require "rails_helper"

RSpec.describe ItemsListUpdateWorker do
  subject(:perform) { described_class.new.perform(market_hash_names) }

  describe "#perform" do
    context "with new market_hash_names" do
      let(:market_hash_names) { [ "AWP | Asiimov (Field-Tested)", "Fracture Case" ] }

      it "creates one item per name" do
        perform

        asiimov = Item.find_by(market_hash_name: "AWP | Asiimov (Field-Tested)")
        fracture_case = Item.find_by(market_hash_name: "Fracture Case")

        aggregate_failures do
          expect(asiimov).to be_present
          expect(asiimov.weapon_type).to eq("AWP")
          expect(asiimov.item_name).to eq("Asiimov")
          expect(asiimov.condition).to eq("Field-Tested")
          expect(fracture_case).to be_present
          expect(fracture_case.weapon_type).to be_nil
          expect(fracture_case.item_name).to eq("Fracture Case")
        end
      end
    end

    context "with a market_hash_name that already exists" do
      let!(:existing) { create(:item, market_hash_name: "AWP | Asiimov (Field-Tested)") }
      let(:market_hash_names) { [ "AWP | Asiimov (Field-Tested)" ] }

      it "upserts the existing item instead of duplicating it" do
        expect { perform }.not_to change(Item, :count)

        expect(Item.find(existing.id).market_hash_name).to eq("AWP | Asiimov (Field-Tested)")
      end
    end

    context "with an empty array" do
      let(:market_hash_names) { [] }

      it "does nothing" do
        expect { perform }.not_to change(Item, :count)
      end
    end
  end
end
