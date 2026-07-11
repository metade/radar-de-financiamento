require "test_helper"

class EuFundingTendersSourceTest < Minitest::Test
  def test_fetches_and_normalizes_topic_results
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(search_payload, topic_index_body: topic_index_html),
      page_size: 10,
      current_year: 2023
    )

    opportunities = source.fetch

    assert_equal 1, opportunities.size
    opportunity = opportunities.first
    assert_equal "eu-ft-amif-2023-tf2-ag-call-02-local", opportunity.id
    assert_equal "Integration and inclusion at local level", opportunity.title
    assert_equal "AMIF", opportunity.programme
    assert_equal "2026-09-24", opportunity.deadline
    assert_equal "EU Funding & Tenders Portal", opportunity.funding_source
    assert_equal "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/amif-2023-tf2-ag-call-02-local", opportunity.official_link
    assert_includes opportunity.eligible_applicants, "Municípios ou autoridades locais"
    assert_includes opportunity.eligible_applicants, "Entidades públicas"
    assert_includes opportunity.themes, "community_development"
    assert_includes opportunity.themes, "inclusion"
  end

  def test_extracts_topic_ids_from_noisy_results_and_fetches_exact_topic_records
    client = SequencedHttpClient.new([noisy_seed_payload, current_topic_payload])
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: client,
      terms: ["climate adaptation"],
      topic_ids: [],
      current_year: 2026
    )

    opportunities = source.fetch

    assert_equal 1, opportunities.size
    assert_equal "eu-ft-horizon-cl6-2026-02-climate-02", opportunities.first.id
    assert_equal "Towards the water infrastructures of the future", opportunities.first.title
    assert_equal 2, client.requested_urls.size
    assert_includes client.requested_urls.last, "HORIZON-CL6-2026-02-CLIMATE-02"
  end

  def test_prefers_rich_topic_record_when_search_returns_thin_json_record_first
    client = FakeHttpClient.new(thin_and_rich_topic_payload)
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: client,
      topic_ids: ["HORIZON-CL6-2026-01-CIRCBIO-04"],
      current_year: 2026
    )

    opportunities = source.fetch

    assert_equal 1, opportunities.size
    assert_equal "eu-ft-horizon-cl6-2026-01-circbio-04", opportunities.first.id
    assert_equal "2026-09-17", opportunities.first.deadline
    assert_includes client.requested_urls.first, "text=%22HORIZON-CL6-2026-01-CIRCBIO-04%22"
  end

  def test_extracts_deadline_from_nested_plural_deadline_field
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(nested_deadline_topic_payload),
      topic_ids: ["HORIZON-MISS-2026-01-CLIMA-02"],
      current_year: 2026
    )

    assert_equal "2026-09-23", source.fetch.first.deadline
  end

  def test_single_topic_does_not_expand_to_related_topic_results
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(search_payload_with_related_topics),
      topic_ids: ["HORIZON-MISS-2026-01-CLIMA-02"],
      current_year: 2026,
      single_topic: true
    )

    assert_equal ["eu-ft-horizon-miss-2026-01-clima-02"], source.fetch.map(&:id)
  end

  def test_keeps_english_text_when_deadline_comes_from_localized_rich_record
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(localized_topic_payload),
      topic_ids: ["HORIZON-MISS-2026-01-CLIMA-02"],
      current_year: 2026,
      single_topic: true
    )

    opportunity = source.fetch.first

    assert_equal "Facilitating implementation of actionable solutions for climate adaptation of regions and local authorities", opportunity.title
    assert_equal "2026-09-23", opportunity.deadline
  end

  def test_enriches_explicit_topic_even_when_noisy_results_precede_it
    noisy_results = Array.new(45) do |index|
      {
        "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-CL6-2026-01-NOISE-#{index}",
        "metadata" => {"identifier" => ["HORIZON-CL6-2026-01-NOISE-#{index}"], "title" => ["Noise #{index}"]}
      }
    end
    payload = JSON.parse(localized_topic_payload)
    payload["results"] = noisy_results + payload["results"]

    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(payload.to_json),
      topic_ids: ["HORIZON-MISS-2026-01-CLIMA-02"],
      current_year: 2026,
      single_topic: true
    )

    assert_equal "2026-09-23", source.fetch.first.deadline
  end

  def test_does_not_infer_local_relevance_from_substrings_or_portal_links
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(cancer_capacity_payload),
      topic_ids: ["HORIZON-MISS-2026-02-CANCER-06"],
      current_year: 2026
    )

    opportunity = source.fetch.first

    assert_empty opportunity.eligible_applicants
    refute_includes opportunity.themes, "community_development"
    refute_includes opportunity.themes, "civic_participation"
    refute_includes opportunity.themes, "digital_public_services"
    assert_empty opportunity.partnership_requirements
  end

  def test_discovers_current_year_topic_ids_from_official_topic_index
    client = FakeHttpClient.new(search_payload, topic_index_body: topic_index_html)
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: client,
      current_year: 2026,
      max_topic_ids: 2
    )

    source.fetch

    assert_equal 2, client.requested_urls.size
    assert_includes client.requested_urls.first, "HORIZON-MISS-2026-CLIMA-01-01"
    assert_includes client.requested_urls.last, "LIFE-2026-SAP-CLIMA"
  end

  def test_ignores_non_topic_results
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(faq_payload),
      topic_ids: ["AMIF-2023-TF2-AG-CALL-02-LOCAL"]
    )

    assert_empty source.fetch
  end

  def test_ignores_closed_topic_results
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new(closed_topic_payload),
      topic_ids: ["AMIF-2023-TF2-AG-CALL-02-LOCAL"],
      current_year: 2023
    )

    assert_empty source.fetch
  end

  def test_returns_empty_array_when_api_response_is_unusable
    source = FundingRadar::Sources::EuFundingTendersSource.new(
      http_client: FakeHttpClient.new("not-json"),
      topic_ids: ["AMIF-2023-TF2-AG-CALL-02-LOCAL"]
    )

    assert_empty source.fetch
  end

  private

  class FakeHttpClient
    attr_reader :requested_urls

    def initialize(body, topic_index_body: "")
      @body = body
      @topic_index_body = topic_index_body
      @requested_urls = []
    end

    def get(_url, headers: {})
      @topic_index_body
    end

    def post_json(url, headers: {})
      @requested_urls << url
      @body
    end
  end

  class SequencedHttpClient
    attr_reader :requested_urls

    def initialize(bodies)
      @bodies = bodies.dup
      @requested_urls = []
    end

    def get(_url, headers: {})
      ""
    end

    def post_json(url, headers: {})
      @requested_urls << url
      @bodies.shift
    end
  end

  def topic_index_html
    <<~HTML
      <a href="https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/amif-2025-old">AMIF-2025-OLD</a>
      <a href="https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/horizon-miss-2026-clima-01-01">HORIZON-MISS-2026-CLIMA-01-01</a>
      <a href="https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/life-2026-sap-clima">LIFE-2026-SAP-CLIMA</a>
      <a href="https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/unknown-2026-topic">UNKNOWN-2026-TOPIC</a>
    HTML
  end

  def search_payload
    {
      "results" => [
        {
          "reference" => "AMIF-2023-TF2-AG-CALL-02-LOCAL",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/data/topicDetails/AMIF-2023-TF2-AG-CALL-02-LOCAL.json",
          "summary" => "Support for integration and inclusion in municipalities and local communities.",
          "content" => "<b>Integration and inclusion at local level</b>",
          "metadata" => {
            "esST_title" => ["Integration and inclusion at local level"],
            "callDeadlineDate" => ["2026-09-24T17:00:00+0200"],
            "esST_programmeName" => ["AMIF"],
            "esIN_keyword" => ["municipalities", "local authorities", "public authorities", "inclusion", "community"]
          }
        }
      ]
    }.to_json
  end

  def noisy_seed_payload
    {
      "results" => [
        {
          "reference" => "50912",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/support/faq/50912",
          "summary" => "FAQ mentioning HORIZON-CL6-2026-02-CLIMATE-02 for local authorities.",
          "metadata" => {
            "DATASOURCE" => ["SEDIA_FAQ"],
            "esIN_keyword" => ["HORIZON-CL6-2026-02-CLIMATE-02", "local authorities"]
          }
        }
      ]
    }.to_json
  end

  def current_topic_payload
    {
      "results" => [
        {
          "reference" => "123",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-CL6-2026-02-CLIMATE-02.json",
          "summary" => "Towards the water infrastructures of the future",
          "content" => "Water infrastructure and climate resilience for local authorities",
          "metadata" => {
            "identifier" => ["HORIZON-CL6-2026-02-CLIMATE-02"],
            "title" => ["Towards the water infrastructures of the future"],
            "deadlineDate" => ["2026-09-24T17:00:00+0200"],
            "frameworkProgramme" => ["HORIZON2027"],
            "tags" => ["climate", "water", "local authorities"]
          }
        }
      ]
    }.to_json
  end

  def thin_and_rich_topic_payload
    {
      "results" => [
        {
          "reference" => "501460096141222",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-CL6-2026-01-CIRCBIO-04.json",
          "summary" => "Thin search document",
          "metadata" => {
            "identifier" => ["HORIZON-CL6-2026-01-CIRCBIO-04"],
            "title" => ["Textile circularity systems"],
            "startDate" => ["2026-05-05T07:57:38.395+0000"]
          }
        },
        {
          "reference" => "50146009TOPICSen",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-CL6-2026-01-CIRCBIO-04",
          "summary" => "Rich topic document",
          "metadata" => {
            "identifier" => ["HORIZON-CL6-2026-01-CIRCBIO-04"],
            "title" => ["Textile circularity systems"],
            "status" => ["31094502"],
            "sortStatus" => ["1"],
            "actions" => ["[{\"deadlineDates\":[\"2026-09-17\"]}]"]
          }
        }
      ]
    }.to_json
  end

  def cancer_capacity_payload
    {
      "results" => [
        {
          "reference" => "50152099TOPICSen",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-MISS-2026-02-CANCER-06",
          "summary" => "Development of a research capacity building programme on cancer with and for Ukraine",
          "content" => "Research capacities, patients and citizens, digital capacity, and the European Atomic Energy Community.",
          "metadata" => {
            "identifier" => ["HORIZON-MISS-2026-02-CANCER-06"],
            "title" => ["Development of a research capacity building programme on cancer with and for Ukraine"],
            "deadlineDate" => ["2026-09-15T00:00:00.000+0000"],
            "links" => ["https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/how-to-participate/partner-search"]
          }
        }
      ]
    }.to_json
  end

  def nested_deadline_topic_payload
    {
      "results" => [
        {
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-MISS-2026-01-CLIMA-02",
          "summary" => "Facilitating implementation of actionable solutions for climate adaptation of regions and local authorities",
          "metadata" => {
            "identifier" => ["HORIZON-MISS-2026-01-CLIMA-02"],
            "title" => ["Facilitating implementation of actionable solutions for climate adaptation of regions and local authorities"],
            "actions" => [
              {"dates" => {"openingDate" => "2026-02-04", "deadlineDates" => ["2026-09-23T17:00:00+0200"]}}
            ]
          }
        }
      ]
    }.to_json
  end

  def search_payload_with_related_topics
    {
      "results" => [
        JSON.parse(nested_deadline_topic_payload).fetch("results").first,
        {
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-MISS-2026-01-CLIMA-03",
          "metadata" => {
            "identifier" => ["HORIZON-MISS-2026-01-CLIMA-03"],
            "title" => ["Related topic"]
          }
        }
      ]
    }.to_json
  end

  def localized_topic_payload
    {
      "results" => [
        {
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-MISS-2026-01-CLIMA-02.json",
          "summary" => "Facilitating implementation of actionable solutions for climate adaptation of regions and local authorities",
          "content" => "Climate adaptation of regions and local authorities",
          "metadata" => {
            "identifier" => ["HORIZON-MISS-2026-01-CLIMA-02"],
            "title" => ["Facilitating implementation of actionable solutions for climate adaptation of regions and local authorities"],
            "language" => ["en"],
            "callIdentifier" => ["HORIZON-MISS-2026-1"]
          }
        },
        {
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-MISS-2026-01-CLIMA-02.json",
          "summary" => "Ułatwianie wdrażania wykonalnych rozwiązań w zakresie przystosowania się regionów i władz lokalnych do zmiany klimatu",
          "metadata" => {
            "identifier" => ["HORIZON-MISS-2026-01-CLIMA-02"],
            "title" => ["Ułatwianie wdrażania wykonalnych rozwiązań w zakresie przystosowania się regionów i władz lokalnych do zmiany klimatu"],
            "language" => ["pl"],
            "deadlineDate" => ["2026-09-23T00:00:00.000+0000"],
            "actions" => ["[{\"deadlineDates\":[\"2026-09-23\"]}]"],
            "status" => ["31094502"]
          }
        }
      ]
    }.to_json
  end

  def faq_payload
    {
      "results" => [
        {
          "reference" => "71653",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/support/faq/71653",
          "summary" => "Can cities or municipalities apply to the call?",
          "metadata" => {"DATASOURCE" => ["SEDIA_FAQ"]}
        }
      ]
    }.to_json
  end

  def closed_topic_payload
    {
      "results" => [
        {
          "reference" => "45707448AMIFProjectGrants1673913600000",
          "url" => "https://ec.europa.eu/info/funding-tenders/opportunities/data/topicDetails/AMIF-2023-TF2-AG-CALL-02-LOCAL.json",
          "summary" => "Integration and inclusion at regional and local level",
          "metadata" => {
            "identifier" => ["AMIF-2023-TF2-AG-CALL-02-LOCAL"],
            "title" => ["Integration and inclusion at regional and local level"],
            "status" => ["31094503"],
            "actions" => ["[{\"status\":{\"description\":\"Closed\"}}]"]
          }
        }
      ]
    }.to_json
  end
end
