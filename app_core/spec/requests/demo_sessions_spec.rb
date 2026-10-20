require "rails_helper"

RSpec.describe "Demo sessions", type: :request, demo_redis: true do
  describe "POST /demo_session" do
    it "creates a Redis session, stores the cookie, and redirects" do
      expect { post demo_session_path }.not_to change(User, :count)

      aggregate_failures do
        expect(response).to redirect_to(root_path)
        expect(demo_session_keys.size).to eq(1)
        expect(response.cookies["demo_id"]).to be_present
      end
    end

    it "renders the demo dashboard after the redirect" do
      post demo_session_path
      follow_redirect!

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to include('data-demo="true"')
        expect(response.body).to match(/data-demo-token="[^"]+"/)
        expect(response.body).to include("My account")
        expect(response.body).to include("Exit demo")
        expect(response.body).not_to include("Sign in through Steam")
      end
    end

    it "replaces an existing demo session" do
      post demo_session_path
      first_key = demo_session_keys.first

      post demo_session_path
      second_key = demo_session_keys.first

      aggregate_failures do
        expect(first_key).to be_present
        expect(second_key).to be_present
        expect(second_key).not_to eq(first_key)
        expect(Demo::SessionStore.find(T.must(first_key).delete_prefix("demo:session:"))).to be_nil
        expect(Demo::SessionStore.find(T.must(second_key).delete_prefix("demo:session:"))).to be_present
      end
    end
  end

  describe "DELETE /demo_session" do
    it "deletes the Redis session and returns to the signed-out screen" do
      post demo_session_path
      demo_key = T.must(demo_session_keys.first)

      delete demo_session_path
      follow_redirect!

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(DEMO_REDIS_POOL.with { |redis| redis.get(demo_key) }).to be_nil
        expect(response.body).to include("Try a demo account")
        expect(response.body).not_to include('data-demo="true"')
      end
    end
  end

  describe "an expired demo session" do
    it "clears the cookie and renders the signed-out screen when Redis no longer has the key" do
      post demo_session_path
      clear_demo_redis

      get root_path

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Try a demo account")
        expect(response.body).not_to include('data-demo="true"')
        expect(response.body).not_to match(/data-demo-token="[^"]+"/)
      end
    end
  end
end
