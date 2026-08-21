require "test_helper"

class DashboardsControllerTest < ActionController::TestCase
  tests DashboardsController

  test "redirects to root when not signed in" do
    get :show
    assert_redirected_to root_path
  end

  test "renders the dashboard page when signed in" do
    sign_in_as(users(:one))

    get :show
    assert_response :success
  end

  test "json endpoint returns the shape the React app expects" do
    sign_in_as(users(:one))

    stub_request(:get, %r{/api/v1/inventories/}).to_return(
      status: 200,
      body: {
        items_count: 1,
        items: [
          { market_hash_name: "AK-47 | Redline (Field-Tested)",
            item_type: nil,
            metadata: { weapon_type: "AK-47", item_name: "Redline", condition: "Field-Tested", stattrak: false },
            current_price_cents: 3845,
            change_24h_cents: nil }
        ]
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    get :show, format: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 1, json["items_count"]
    assert json["items"].first.key?("change_24h_cents")
    refute_nil json["items"].first["change_24h_cents"]
    assert json["portfolio"]["series"].key?("7d")
    assert json["market_volume"].key?("count_24h")
  end

  test "json endpoint tolerates app_fetcher being unreachable" do
    sign_in_as(users(:one))

    stub_request(:get, %r{/api/v1/inventories/}).to_timeout

    get :show, format: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["items_count"]
    assert_equal [], json["items"]
  end

  private

  def sign_in_as(user)
    session[:user_id] = user.id
  end
end
