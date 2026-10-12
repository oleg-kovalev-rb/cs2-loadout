require "rails_helper"

RSpec.describe AdminUser do
  describe "validations" do
    it "requires an email" do
      admin_user = build(:admin_user, email: nil)

      expect(admin_user).not_to be_valid
    end

    it "requires a unique email" do
      create(:admin_user, email: "admin@example.com")
      admin_user = build(:admin_user, email: "admin@example.com")

      expect(admin_user).not_to be_valid
    end

    it "treats email uniqueness as case-insensitive" do
      create(:admin_user, email: "admin@example.com")
      admin_user = build(:admin_user, email: "ADMIN@example.com")

      expect(admin_user).not_to be_valid
    end

    it "rejects a malformed email" do
      admin_user = build(:admin_user, email: "not-an-email")

      expect(admin_user).not_to be_valid
    end
  end

  describe "email normalization" do
    it "downcases the email before saving" do
      admin_user = create(:admin_user, email: "Mixed.Case@Example.com")

      expect(admin_user.email).to eq("mixed.case@example.com")
    end
  end

  describe "has_secure_password" do
    it "authenticates with the correct password" do
      admin_user = create(:admin_user, password: "correct horse battery staple")

      expect(admin_user.authenticate("correct horse battery staple")).to eq(admin_user)
    end

    it "does not authenticate with the wrong password" do
      admin_user = create(:admin_user, password: "correct horse battery staple")

      expect(admin_user.authenticate("wrong password")).to eq(false)
    end
  end
end
