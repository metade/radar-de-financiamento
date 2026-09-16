module FundingRadar
  module DataQuality
    MAX_SUMMARY_LENGTH = 600
    NAVIGATION_PATTERNS = [
      /cookie|accessibility statement|skip to content|menu|search|subscribe|follow us/i,
      /facebook|instagram|linkedin|youtube|privacy policy|terms and conditions/i,
      /home\s+(?:about|contact|news)|(?:about|contact|news)\s+home/i
    ].freeze

    module_function

    def summary(value, title:, fallback: nil)
      candidate = normalize(value)
      return normalize(fallback) if unusable_summary?(candidate, title) && fallback
      return nil if unusable_summary?(candidate, title)

      candidate[0, MAX_SUMMARY_LENGTH].strip
    end

    def unusable_summary?(value, title)
      value.empty? || near_title?(value, title) || navigation?(value) || value.scan(%r{https?://|www\.}i).length >= 2
    end

    def near_title?(summary, title)
      normalize_for_comparison(summary) == normalize_for_comparison(title)
    end

    def navigation?(value)
      NAVIGATION_PATTERNS.count { |pattern| value.match?(pattern) } >= 2 || value.split.length > 110
    end

    def normalize(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def normalize_for_comparison(value)
      normalize(value).downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip
    end

    def warnings(summary, title:, themes: [])
      result = []
      result << "summary matches title" if near_title?(summary, title)
      result << "summary is empty" if normalize(summary).empty?
      result << "summary contains navigation or boilerplate" if navigation?(normalize(summary))
      result << "summary contains repeated links" if normalize(summary).scan(%r{https?://|www\.}i).length >= 2
      result << "unusually broad theme set" if Array(themes).size > 4
      result
    end
  end
end
