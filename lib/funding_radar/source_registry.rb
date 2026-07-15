module FundingRadar
  class SourceRegistry
    def initialize(sources:)
      @sources = sources
    end

    def fetch_all
      @sources.flat_map do |source|
        name = source.class.name.to_s.split("::").last.to_s
        name = "anonymous source" if name.empty?
        opportunities = Debug.timed("source #{name}") { source.fetch }
        Debug.failure "source #{name} returned no opportunities" if opportunities.empty?
        Debug.status "source #{name}: #{opportunities.size} opportunities"
        opportunities
      end
    end
  end
end
