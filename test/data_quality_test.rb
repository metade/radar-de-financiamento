require "test_helper"

class DataQualityTest < Minitest::Test
  def test_rejects_title_only_and_navigation_summaries
    assert_nil FundingRadar::DataQuality.summary("A call", title: "A call")
    assert_nil FundingRadar::DataQuality.summary(
      "Home About Contact News Cookie settings Privacy policy Follow us",
      title: "A call"
    )
  end

  def test_keeps_a_compact_meaningful_summary
    summary = FundingRadar::DataQuality.summary(
      "Apoia municípios na melhoria da acessibilidade de edifícios públicos.",
      title: "Acessibilidade de edifícios públicos"
    )

    assert_equal "Apoia municípios na melhoria da acessibilidade de edifícios públicos.", summary
  end

  def test_opportunity_distinguishes_unknown_applicants_and_limits_themes
    opportunity = FundingRadar::Opportunity.from_hash(
      "id" => "x", "title" => "X", "programme" => "P", "funding_source" => "S",
      "official_link" => "https://example.test", "summary" => "S",
      "themes" => %w[climate environment mobility inclusion equality]
    )

    assert_equal "unknown", opportunity.applicant_eligibility_status
    assert_equal %w[climate environment mobility inclusion equality], opportunity.themes
  end
end
