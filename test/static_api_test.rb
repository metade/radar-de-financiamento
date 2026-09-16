require "json"
require "test_helper"

class StaticApiTest < Minitest::Test
  def test_writes_static_api_files_with_compact_current_catalogue
    Dir.mktmpdir do |dir|
      builder = FundingRadar::StaticApi::Builder.new(reports: reports)
      builder.write(dir)

      meta = JSON.parse(File.read(File.join(dir, "api/v1/meta.json")))
      catalog = JSON.parse(File.read(File.join(dir, "api/v1/catalog.json")))
      schema = JSON.parse(File.read(File.join(dir, "api/v1/schema.json")))

      assert_equal 2, meta.fetch("opportunity_count")
      assert_equal 1, meta.fetch("catalog_count")
      assert_equal ["open-id"], catalog.map { |entry| entry.fetch("id") }
      assert_equal "https://official.example/open", catalog.first.fetch("source_url")
      assert_equal "known", catalog.first.fetch("applicant_eligibility_status")
      assert_equal "known", JSON.parse(File.read(File.join(dir, "api/v1/opportunities/open-id.json"))).dig("facts", "applicant_eligibility_status")
      refute catalog.first.key?("relevance_score")
      refute catalog.first.key?("_report_generated_at")
      assert_operator JSON.generate(catalog).bytesize, :<, 1_000
      assert_equal "object", schema.fetch("type")

      catalog.each do |entry|
        path = File.join(dir, entry.fetch("detail_url").delete_prefix("/"))
        assert File.file?(path), "missing #{path}"
        detail = JSON.parse(File.read(path))
        assert_equal entry.fetch("id"), detail.fetch("id")
        assert_match(/\A[a-z0-9][a-z0-9._~-]*\z/, detail.fetch("id"))
        assert_equal "https://official.example/open", detail.dig("links", "source_url")
        refute_includes JSON.generate(detail), "debug"
        refute_includes JSON.generate(detail), "_report_generated_at"
        assert detail.fetch("facts").is_a?(Hash)
        assert detail.fetch("analysis").fetch("summary").is_a?(String)
      end

      Dir[File.join(dir, "api/v1/opportunities/*.json")].each do |path|
        detail = JSON.parse(File.read(path))
        assert_equal %w[analysis facts id links programme provenance status title].sort, detail.keys.sort
        assert detail.fetch("facts").is_a?(Hash)
        assert detail.fetch("analysis").is_a?(Hash)
        assert detail.fetch("provenance").is_a?(Hash)
        assert detail.fetch("links").is_a?(Hash)
      end
    end
  end

  def test_latest_report_wins_and_ids_are_deterministic
    first = reports.first
    second = {
      "generated_at" => "2026-09-16T12:00:00Z",
      "opportunities" => [first.fetch("opportunities").first.merge("summary" => "Updated")]
    }

    first_builder = FundingRadar::StaticApi::Builder.new(reports: [first])
    second_builder = FundingRadar::StaticApi::Builder.new(reports: [second, first])

    assert_equal first_builder.records.keys, second_builder.records.keys
    assert_equal "Updated", second_builder.records.values.first.dig("analysis", "summary")
    assert_equal first_builder.records.keys, FundingRadar::StaticApi::Builder.new(reports: [first]).records.keys
  end

  def test_schema_describes_required_public_sections
    schema = FundingRadar::StaticApi::Builder.schema

    assert_equal %w[id title programme status facts analysis provenance links], schema.fetch("required")
    assert_equal %w[open closed unknown], schema.dig("properties", "status", "enum")
    assert_equal "date", schema.dig("$defs", "facts", "properties", "deadline", "format")
      assert_equal "date-time", schema.dig("$defs", "provenance", "properties", "report_generated_at", "format")
      assert_equal %w[known unknown], schema.dig("$defs", "facts", "properties", "applicant_eligibility_status", "enum")
  end

  private

  def reports
    [{
      "generated_at" => "2026-09-15T12:00:00Z",
      "opportunities" => [
        {
          "id" => "open-id",
          "title" => "Open opportunity",
          "programme" => "Programme",
          "opening_date" => "2026-01-01",
          "deadline" => "2099-12-31",
          "funding_amount" => "€10,000",
          "funding_source" => "Official source",
          "official_link" => "https://official.example/open",
          "document_link" => "https://official.example/open.pdf",
          "eligible_applicants" => ["municipality"],
          "partnership_requirements" => "",
          "other_requirements" => "",
          "summary" => "Short summary",
          "themes" => ["climate"],
          "relevance_score" => 80,
          "relevance_category" => "Altamente relevante",
          "relevance_explanation" => "Relevant",
          "llm_analysis" => {"summary" => "Interpretation"}
        },
        {
          "id" => "expired-id",
          "title" => "Expired opportunity",
          "programme" => "Programme",
          "deadline" => "2020-01-01",
          "funding_source" => "Official source",
          "official_link" => "https://official.example/expired",
          "summary" => "Expired summary",
          "themes" => []
        }
      ]
    }]
  end
end
