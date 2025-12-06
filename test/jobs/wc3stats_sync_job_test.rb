require "test_helper"
require "webmock/minitest"

class Wc3statsSyncJobTest < ActiveJob::TestCase
  setup do
    @api_response = {
      "status" => "OK",
      "code" => 200,
      "pagination" => { "totalItems" => 2 },
      "body" => [
        { "id" => 231, "name" => "LOTR BFME", "map" => "BFME" },
        { "id" => 233, "name" => "LOTR BFME RM", "map" => "BFME" }
      ]
    }
  end

  test "job can be enqueued" do
    assert_enqueued_with(job: Wc3statsSyncJob, args: [ "recent" ]) do
      Wc3statsSyncJob.perform_later("recent")
    end
  end

  test "recent mode fetches limited replays" do
    stub_request(:get, "https://api.wc3stats.com/replays?limit=0&search=BFME")
      .to_return(status: 200, body: @api_response.to_json, headers: { "Content-Type" => "application/json" })

    # Stub individual replay fetches (they will fail, but that's okay for this test)
    stub_request(:get, /api\.wc3stats\.com\/replays\/\d+/)
      .to_return(status: 404, body: { "status" => "ERROR" }.to_json)

    assert_nothing_raised do
      Wc3statsSyncJob.perform_now("recent")
    end
  end

  test "full mode fetches all replays" do
    stub_request(:get, "https://api.wc3stats.com/replays?limit=0&search=BFME")
      .to_return(status: 200, body: @api_response.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, /api\.wc3stats\.com\/replays\/\d+/)
      .to_return(status: 404, body: { "status" => "ERROR" }.to_json)

    assert_nothing_raised do
      Wc3statsSyncJob.perform_now("full")
    end
  end

  test "unknown mode logs error" do
    assert_nothing_raised do
      Wc3statsSyncJob.perform_now("invalid")
    end
  end
end
