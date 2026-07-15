require "test_helper"

class SourceBuilderTest < Minitest::Test
  def test_default_sources_exclude_fixtures
    sources = FundingRadar::SourceBuilder.default(
      root: File.expand_path("..", __dir__),
      env: {},
      http_client: Object.new
    )

    assert_equal 6, sources.size
    assert_instance_of FundingRadar::Sources::EuFundingTendersSource, sources.first
    assert_instance_of FundingRadar::Sources::Portugal2030Source, sources[1]
    assert_instance_of FundingRadar::Sources::Lisboa2030Source, sources[2]
    assert_instance_of FundingRadar::Sources::InterregSudoeSource, sources[3]
    assert_instance_of FundingRadar::Sources::EuropeanUrbanInitiativeSource, sources[4]
    assert_instance_of FundingRadar::Sources::TurismoDePortugalSource, sources[5]
  end

  def test_fixtures_are_opt_in
    sources = FundingRadar::SourceBuilder.default(
      root: File.expand_path("..", __dir__),
      env: {"INCLUDE_FIXTURES" => "true"},
      http_client: Object.new
    )

    assert_equal 7, sources.size
    assert_instance_of FundingRadar::Sources::EuFundingTendersSource, sources.first
    assert_instance_of FundingRadar::Sources::FixtureSource, sources.last
  end
end
