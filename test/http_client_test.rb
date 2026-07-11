require "test_helper"

class HttpClientTest < Minitest::Test
  def test_caches_successful_get_responses
    Dir.mktmpdir do |directory|
      requests = 0
      client = FundingRadar::HttpClient.new(cache_path: directory, requester: response_for("cached body", -> { requests += 1 }))

      assert_equal "cached body", client.get("https://example.test/topics", headers: {"Accept" => "text/html"})
      assert_equal "cached body", client.get("https://example.test/topics", headers: {"Accept" => "text/html"})
      assert_equal 1, requests
    end
  end

  def test_caches_post_responses_separately_from_get_responses
    Dir.mktmpdir do |directory|
      requests = 0
      client = FundingRadar::HttpClient.new(cache_path: directory, requester: response_for("cached body", -> { requests += 1 }))

      client.get("https://example.test/search")
      client.post_json("https://example.test/search")
      client.post_json("https://example.test/search")

      assert_equal 2, requests
    end
  end

  def test_can_bypass_cache
    requests = 0
    client = FundingRadar::HttpClient.new(cache: false, requester: response_for("fresh body", -> { requests += 1 }))

    client.get("https://example.test/topics")
    client.get("https://example.test/topics")

    assert_equal 2, requests
  end

  private

  def response_for(body, counter)
    lambda do |_uri, _request|
      counter.call
      FakeResponse.new(body)
    end
  end

  class FakeResponse < Net::HTTPSuccess
    def initialize(body)
      super("1.1", "200", "OK")
      @test_body = body
    end

    def body
      @test_body
    end
  end
end
