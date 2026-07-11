require "net/http"
require "uri"

module FundingRadar
  class HttpClient
    DEFAULT_HEADERS = {
      "Accept-Encoding" => "identity",
      "User-Agent" => "eu-funding-radar/0.1"
    }.freeze
    RETRIES = 2

    def get(url, headers: {})
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request_with_retries(uri, request, headers)
    end

    def post_json(url, headers: {})
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request_with_retries(uri, request, headers)
    end

    private

    def request_with_retries(uri, request, headers)
      DEFAULT_HEADERS.merge(headers).each { |key, value| request[key] = value }

      attempts = 0
      begin
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout = 10
          http.read_timeout = 30
          http.request(request)
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
