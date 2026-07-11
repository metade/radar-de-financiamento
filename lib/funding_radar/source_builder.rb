module FundingRadar
  class SourceBuilder
    def self.default(root:, env: ENV, http_client: HttpClient.new)
      sources = [
        Sources::EuFundingTendersSource.new(http_client: http_client)
      ]

      if env.fetch("INCLUDE_FIXTURES", "false") == "true"
        sources << Sources::FixtureSource.new(path: File.join(root, "data/sources/fixtures.yml"))
      end

      sources
    end
  end
end
