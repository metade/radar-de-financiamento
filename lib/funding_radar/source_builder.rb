module FundingRadar
  class SourceBuilder
    def self.default(root:, env: ENV, http_client: nil)
      http_client ||= HttpClient.new(
        cache: env.fetch("FUNDING_RADAR_CACHE", "true") == "true",
        cache_path: env.fetch("FUNDING_RADAR_CACHE_DIR", File.join(root, "tmp/cache/funding_radar")),
        cache_expires_in: env.fetch("FUNDING_RADAR_CACHE_TTL", HttpClient::DEFAULT_CACHE_TTL.to_s).to_i
      )

      sources = [
        Sources::EuFundingTendersSource.new(http_client: http_client),
        Sources::Portugal2030Source.new(http_client: http_client)
      ]

      if env.fetch("INCLUDE_FIXTURES", "false") == "true"
        sources << Sources::FixtureSource.new(path: File.join(root, "data/sources/fixtures.yml"))
      end

      sources
    end
  end
end
