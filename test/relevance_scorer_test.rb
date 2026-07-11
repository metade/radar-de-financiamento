require "test_helper"

class RelevanceScorerTest < Minitest::Test
  def test_scores_local_authority_opportunity_as_highly_relevant
    opportunity = FundingRadar::Opportunity.from_hash(
      "id" => "test",
      "title" => "Participação local",
      "programme" => "CERV",
      "deadline" => "2026-07-20",
      "funding_source" => "Comissão Europeia",
      "official_link" => "https://example.test/call",
      "eligible_applicants" => ["Municípios"],
      "partnership_requirements" => "Parceria europeia.",
      "summary" => "Apoio a participação local.",
      "themes" => ["civic_participation", "community_development", "equality"]
    )

    result = FundingRadar::RelevanceScorer.new.score(opportunity, today: Date.new(2026, 7, 11))

    assert_operator result.score, :>=, 75
    assert_equal "Altamente relevante", result.category
    assert_match "autarquias", result.explanation
  end

  def test_scores_non_public_applicant_opportunity_lower
    opportunity = FundingRadar::Opportunity.from_hash(
      "id" => "test",
      "title" => "Cultura",
      "programme" => "Europa Criativa",
      "deadline" => "2026-12-20",
      "funding_source" => "Comissão Europeia",
      "official_link" => "https://example.test/culture",
      "eligible_applicants" => ["Associações culturais"],
      "partnership_requirements" => "Consórcio.",
      "summary" => "Apoio cultural.",
      "themes" => ["community_development"]
    )

    result = FundingRadar::RelevanceScorer.new.score(opportunity, today: Date.new(2026, 7, 11))

    assert_equal "Prioridade baixa", result.category
    assert_match "faltam sinais fortes", result.explanation
  end

  def test_prioritizes_lisbon_or_aml_opportunities
    opportunity = FundingRadar::Opportunity.from_hash(
      "id" => "lisbon",
      "title" => "Mobilidade urbana sustentável",
      "programme" => "SUSTENTAVEL2030",
      "funding_source" => "Portugal 2030",
      "official_link" => "https://example.test/lisbon",
      "eligible_applicants" => ["Entidades públicas"],
      "other_requirements" => "FEDER · AML",
      "summary" => "Apoio à mobilidade urbana.",
      "themes" => ["mobility"]
    )

    result = FundingRadar::RelevanceScorer.new.score(opportunity, today: Date.new(2026, 7, 11))

    assert_equal 67, result.score
    assert_match "Lisboa", result.explanation
  end
end
