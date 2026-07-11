require "test_helper"

class InterregSudoeSourceTest < Minitest::Test
  FakeHttpClient = Struct.new(:pages) do
    def get(url, headers: {})
      pages.fetch(url)
    end
  end

  def test_fetches_open_calls_from_official_pages
    index_url = "https://example.test/open"
    pages = {
      index_url => '<a href="/3rd-call/">3rd</a><a href="/4th-call/">4th</a> 4 may 2026 30 september 2026',
      "https://example.test/3rd-call/" => '<h1>3rd call (open)</h1><p>Launch of the 3rd Interreg Sudoe call: Focus on capitalisation</p><h2>Call budget</h2><p>ERDF budget amounts € 1,000,000</p><p>Public authorities and ageing population.</p>',
      "https://example.test/4th-call/" => '<h1>4th call (open)</h1><p>Taking action against wildfires and population ageing</p><h2>Call budget</h2><p>Available ERDF funding € 4,000,000</p>'
    }
    source = FundingRadar::Sources::InterregSudoeSource.new(
      http_client: FakeHttpClient.new(pages),
      index_url: index_url,
      call_urls: ["https://example.test/3rd-call/", "https://example.test/4th-call/"]
    )

    opportunities = source.fetch

    assert_equal ["sudoe-3rd-call", "sudoe-4th-call"], opportunities.map(&:id)
    assert_equal "2026-05-04", opportunities.first.opening_date
    assert_equal "2026-09-30", opportunities.first.deadline
    assert_equal "€1,000,000", opportunities.first.funding_amount
    assert_includes opportunities.first.eligible_applicants, "Entidades públicas"
    assert_includes opportunities.last.themes, "climate"
    assert_equal "Taking action against wildfires and population ageing", opportunities.last.summary
  end

  def test_discovers_future_call_urls_and_skips_closed_calls
    index_url = "https://example.test/calls"
    pages = {
      index_url => '<a href="/priority-4-call/">Priority 4</a><a href="/5th-call/">5th</a>',
      "https://example.test/priority-4-call/" => '<title>Priority 4 call (upcoming) - Interreg Sudoe</title><h1>Priority 4 call (upcoming)</h1><p>Strengthen Sudoe impact capacities in territories.</p>',
      "https://example.test/5th-call/" => '<title>5th call (closed) - Interreg Sudoe</title><h1>5th call (closed)</h1><p>Closed call.</p>'
    }
    source = FundingRadar::Sources::InterregSudoeSource.new(
      http_client: FakeHttpClient.new(pages),
      index_url: index_url,
      call_urls: [],
      discovery_urls: [index_url]
    )

    opportunities = source.fetch

    assert_equal 1, opportunities.size
    assert_equal "Priority 4 call", opportunities.first.title
    assert_equal "https://example.test/priority-4-call/", opportunities.first.official_link
  end
end
