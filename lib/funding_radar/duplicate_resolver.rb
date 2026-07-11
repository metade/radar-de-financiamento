module FundingRadar
  class DuplicateResolver
    def resolve(opportunities)
      opportunities.each_with_object({}) do |opportunity, seen|
        seen[opportunity.duplicate_key] ||= opportunity
      end.values
    end
  end
end
