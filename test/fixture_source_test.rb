require "test_helper"

class FixtureSourceTest < Minitest::Test
  def test_loads_fixture_opportunities
    source = FundingRadar::Sources::FixtureSource.new(path: File.expand_path("../data/sources/fixtures.yml", __dir__))

    opportunities = source.fetch

    assert_operator opportunities.size, :>=, 3
    assert_equal "Redes de Cidades para Participação Democrática", opportunities.first.title
    assert_includes opportunities.first.eligible_applicants, "Municípios"
  end
end
