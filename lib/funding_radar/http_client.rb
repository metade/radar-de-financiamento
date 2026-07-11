require "net/http"
require "uri"
require "active_support/core_ext/object/blank"

module FundingRadar
  class HttpClient
    DEFAULT_HEADERS = {
      "Accept-Encoding" => "identity",
      "User-Agent" => "eu-funding-radar/0.1"
    }.freeze
    RETRIES = 2
    DEFAULT_CACHE_TTL = 6 * 60 * 60

    def initialize(cache: true, cache_path: ENV.fetch("FUNDING_RADAR_CACHE_DIR", "tmp/cache/funding_radar"), cache_expires_in: ENV.fetch("FUNDING_RADAR_CACHE_TTL", DEFAULT_CACHE_TTL.to_s).to_i, requester: nil)
      @cache = cache ? ActiveSupport::Cache::FileStore.new(cache_path) : nil
      @cache_expires_in = cache_expires_in
      @requester = requester
    end

    def get(url, headers: {})
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      cached_request("GET", url, headers) { request_with_retries(uri, request, headers) }
    end

    def post_json(url, headers: {})
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      cached_request("POST", url, headers) { request_with_retries(uri, request, headers) }
    end

    private

    def cached_request(method, url, headers)
      return yield unless @cache

      @cache.fetch(cache_key(method, url, headers), expires_in: @cache_expires_in) { yield }
    end

    def cache_key(method, url, headers)
      header_key = headers.sort_by { |key, _value| key.to_s.downcase }.map { |key, value| "#{key}:#{value}" }.join("|")
      "v1/#{method}/#{url}/#{header_key}"
    end

    def request_with_retries(uri, request, headers)
      DEFAULT_HEADERS.merge(headers).each { |key, value| request[key] = value }

      attempts = 0
      begin
        response = if @requester
          @requester.call(uri, request)
        else
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
            http.open_timeout = 10
            http.read_timeout = 30
            http.request(request)
          end
        end
      rescue EOFError, IOError, OpenSSL::SSL::SSLError
        attempts += 1
        retry if attempts <= RETRIES
        raise
      end

      raise "HTTP #{response.code} from #{uri.host}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
  end
end
