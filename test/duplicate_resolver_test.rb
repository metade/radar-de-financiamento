require "test_helper"

class DuplicateResolverTest < Minitest::Test
  def test_keeps_first_opportunity_for_same_official_link
    first = opportunity("a", "Primeiro")
    duplicate = opportunity("b", "Duplicado")

    resolved = FundingRadar::DuplicateResolver.new.resolve([first, duplicate])

    assert_equal 1, resolved.size
    assert_equal "Primeiro", resolved.first.title
  end

  private

  def opportunity(id, title)
    FundingRadar::Opportunity.from_hash(
      "id" => id,
      "title" => title,
      "programme" => "LIFE",
      "deadline" => "2026-09-01",
      "funding_source" => "CINEA",
      "official_link" => "https://example.test/same",
      "eligible_applicants" => ["Municípios"],
      "partnership_requirements" => "Sem informação.",
      "summary" => "Resumo.",
      "themes" => ["climate"]
    )
  end
end
