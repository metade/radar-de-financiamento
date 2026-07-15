require "test_helper"

class EuropeanUrbanInitiativeSourceTest < Minitest::Test
  FakeHttpClient = Struct.new(:body) do
    def get(_url, headers: {})
      body
    end
  end

  def test_fetches_open_and_upcoming_catalogue_entries
    html = <<~HTML
      <article>
        <h3>4th EUI Call for Innovative Actions</h3>
        <span>Closed</span>
        <p>Deadline date : 15/06/2026</p>
        <p>Urban authorities</p>
        <p>Support : grant</p>
        <p>Funding support : 2,000,000 €</p>
        <a href="https://www.urban-initiative.eu/call-4">Find out more</a>
      </article>
      <article>
        <h3>City-to-City Exchanges</h3>
        <span>Open</span>
        <p>Deadline date : 17/11/2027</p>
        <p>Urban authorities</p>
        <p>Support : grant</p>
        <p>Funding support : 2,000,000 €</p>
        <a href="/urban-panorama/european-urban-initiative">By European Urban Initiative</a>
        <a href="/city-to-city-kit.pdf">Find out more</a>
      </article>
    HTML

    source = FundingRadar::Sources::EuropeanUrbanInitiativeSource.new(
      http_client: FakeHttpClient.new(html),
      catalogue_url: "https://portico.example/calls"
    )

    opportunities = source.fetch
    opportunity = opportunities.fetch(0)

    assert_equal ["City-to-City Exchanges"], opportunities.map(&:title)
    assert_equal "2027-11-17", opportunity.deadline
    assert_equal "European Urban Initiative", opportunity.funding_source
    assert_equal ["Urban authorities"], opportunity.eligible_applicants
    assert_equal "https://portico.example/urban-panorama/european-urban-initiative", opportunity.official_link
    assert_equal "https://portico.example/city-to-city-kit.pdf", opportunity.document_link
    assert_equal "€2,000,000", opportunity.funding_amount
    assert_includes opportunity.themes, "community_development"
  end
end
