class HomeTest < Spinrail::IntegrationTest
  def test_home
    get "/"
    assert_response :success
  end
end
