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

  def test_recognizes_english_local_authority_eligibility
    opportunity = FundingRadar::Opportunity.from_hash(
      "id" => "eui",
      "title" => "Circular city projects",
      "programme" => "European Urban Initiative",
      "funding_source" => "European Urban Initiative",
      "official_link" => "https://example.test/eui",
      "eligible_applicants" => ["Local/regional authorities, utilities and services"],
      "summary" => "Support for sustainable urban development.",
      "themes" => ["community_development", "environment"]
    )

    result = FundingRadar::RelevanceScorer.new.score(opportunity, today: Date.new(2026, 7, 11))

    assert_equal 80, result.score
    assert_match "aceita autarquias", result.explanation
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

    assert_equal 68, result.score
    assert_match "Lisboa", result.explanation
  end

  def test_does_not_make_a_thematically_similar_research_topic_highly_relevant
    opportunity = FundingRadar::Opportunity.from_hash(
      "id" => "research",
      "title" => "Generative AI for smarter automated transport",
      "programme" => "Horizon Europe",
      "deadline" => "2026-09-30",
      "funding_source" => "EU Funding & Tenders Portal",
      "official_link" => "https://example.test/research",
      "summary" => "Research and innovation for AI, climate and mobility.",
      "themes" => ["climate", "environment", "mobility", "digital_public_services"]
    )

    result = FundingRadar::RelevanceScorer.new.score(opportunity, today: Date.new(2026, 7, 11))

    assert_operator result.score, :<, 75
    assert_equal "Prioridade baixa", result.category
  end

  def test_recognizes_local_policy_impact_without_claiming_eligibility
    opportunity = FundingRadar::Opportunity.from_hash(
      "id" => "green-transition",
      "title" => "Fostering competences for the green transition",
      "programme" => "Horizon Europe",
      "deadline" => "2026-09-23",
      "funding_source" => "EU Funding & Tenders Portal",
      "official_link" => "https://example.test/green-transition",
      "summary" => "Support for policy-makers, communities and education providers in the green transition.",
      "themes" => ["climate", "environment", "equality", "inclusion"]
    )

    result = FundingRadar::RelevanceScorer.new.score(opportunity, today: Date.new(2026, 7, 11))

    assert_equal 73, result.score
    assert_equal "A investigar", result.category
    assert_match "políticas públicas", result.explanation
  end
end
