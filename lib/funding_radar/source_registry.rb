module FundingRadar
  class SourceRegistry
    def initialize(sources:)
      @sources = sources
    end

    def fetch_all
      @sources.flat_map(&:fetch)
    end
  end
end
