module FundingRadar
  module ThemeClassifier
    module_function

    # Subject evidence is deliberately weighted by proximity to the call's
    # meaning. This makes the four-theme presentation limit a ranking decision,
    # rather than an accident of taxonomy declaration order.
    def select(patterns, title:, summary:, description:, subjects: [], limit: 4, minimum_score: 2)
      fields = [[title, 4], [summary, 3], [description, 1], [Array(subjects).join(" "), 2]]
      patterns.filter_map do |theme, theme_patterns|
        score = Array(theme_patterns).sum do |pattern|
          fields.sum { |text, weight| text.to_s.downcase.match?(pattern) ? weight : 0 }
        end
        [theme, score] if score >= minimum_score
      end.sort_by { |theme, score| [-score, theme] }.first(limit).map(&:first)
    end
  end
end
