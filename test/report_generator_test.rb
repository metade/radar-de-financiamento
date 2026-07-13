require "test_helper"
require "csv"

class ReportGeneratorTest < Minitest::Test
  def test_generates_iso_week_report_and_updates_same_week
    Dir.mktmpdir do |dir|
      generator = build_generator(dir)

      first_path = generator.generate(today: Date.new(2026, 7, 11))
      second_path = generator.generate(today: Date.new(2026, 7, 12))

      assert_equal first_path, second_path
      assert_equal File.join(dir, "2026-W28.md"), first_path

      document = YAML.safe_load_file(first_path, permitted_classes: [Date], aliases: false)
      assert_equal "2026-W28", document.fetch("week_id")
      assert_equal "2026-07-12", document.fetch("generated_on")
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/, document.fetch("generated_at"))
      assert_operator document.fetch("opportunities").size, :>=, 1
      assert document.fetch("opportunities").first.key?("relevance_score")
      assert document.fetch("opportunities").first.key?("deadline_status")
      assert document.fetch("disclaimer").include?("documentação oficial")

      csv_path = File.join(dir, "2026-W28.csv")
      assert File.file?(csv_path)
      csv = CSV.read(csv_path, headers: true)
      assert_equal %w[
        id title programme opening_date deadline funding_amount funding_source official_link eligible_applicants
        partnership_requirements other_requirements summary themes relevance_score relevance_category
        relevance_explanation deadline_status
      ], csv.headers
      assert_equal document.fetch("opportunities").size, csv.size
      assert_equal document.fetch("opportunities").first.fetch("id"), csv.first.fetch("id")
      assert_equal document.fetch("opportunities").first.fetch("eligible_applicants").join("; "), csv.first.fetch("eligible_applicants")
    end
  end

  def test_archive_metadata_can_sort_reports_by_generated_date
    Dir.mktmpdir do |dir|
      generator = build_generator(dir)

      generator.generate(today: Date.new(2026, 7, 11))
      generator.generate(today: Date.new(2026, 7, 20))

      reports = Dir[File.join(dir, "*.md")].map do |path|
        YAML.safe_load_file(path, permitted_classes: [Date], aliases: false)
      end

      assert_equal ["2026-W30", "2026-W28"], reports.sort_by { |report| report.fetch("generated_on") }.reverse.map { |report| report.fetch("week_id") }
    end
  end

  def test_can_write_a_mutable_latest_report
    Dir.mktmpdir do |dir|
      generator = build_generator(dir, filename: "latest.md")

      path = generator.generate(today: Date.new(2026, 7, 11))

      assert_equal File.join(dir, "latest.md"), path
      assert File.file?(path)
      assert File.file?(File.join(dir, "latest.csv"))
    end
  end

  def test_both_mode_embeds_both_summaries_in_the_report
    Dir.mktmpdir do |dir|
      processor = Class.new do
        def process(opportunity)
          FundingRadar::LlmProcessing::Result.new(
            opportunity,
            "Resumo LLM.",
            "generated",
            "cache-key",
            nil
          )
        end
      end.new
      generator = build_generator(dir, filename: "latest.md", llm_processor: processor, processing_mode: "both")

      generator.generate(today: Date.new(2026, 7, 11))

      document = YAML.safe_load_file(File.join(dir, "latest.md"), aliases: false)
      assert_equal true, document.fetch("comparison")
      item = document.fetch("opportunities").first
      assert_equal "Resumo LLM.", item.fetch("summary")
      assert item.fetch("deterministic_summary").to_s.length.positive?
    end
  end

  def test_limits_opportunities_per_source_before_duplicate_resolution
    Dir.mktmpdir do |dir|
      opportunities = [
        opportunity("one", "Source A"),
        opportunity("two", "Source A"),
        opportunity("three", "Source B"),
        opportunity("four", "Source B")
      ]
      source = Struct.new(:opportunities) { def fetch = opportunities }.new(opportunities)
      generator = FundingRadar::ReportGenerator.new(
        source_registry: FundingRadar::SourceRegistry.new(sources: [source]),
        duplicate_resolver: FundingRadar::DuplicateResolver.new,
        scorer: FundingRadar::RelevanceScorer.new,
        reports_dir: dir
      )

      path = generator.generate(today: Date.new(2026, 7, 11), tenders_per_source: 1)
      document = YAML.safe_load_file(path, permitted_classes: [Date], aliases: false)

      assert_equal %w[one three], document.fetch("opportunities").map { |item| item.fetch("id") }.sort
    end
  end

  private

  def opportunity(id, source)
    FundingRadar::Opportunity.from_hash(
      "id" => id,
      "title" => "Tender #{id}",
      "programme" => "Programme",
      "funding_source" => source,
      "official_link" => "https://example.test/#{id}",
      "summary" => "Resumo #{id}.",
      "themes" => ["climate"]
    )
  end

  def build_generator(dir, filename: nil, llm_processor: nil, processing_mode: "deterministic")
    source = FundingRadar::Sources::FixtureSource.new(path: File.expand_path("../data/sources/fixtures.yml", __dir__))
    FundingRadar::ReportGenerator.new(
      source_registry: FundingRadar::SourceRegistry.new(sources: [source]),
      duplicate_resolver: FundingRadar::DuplicateResolver.new,
      scorer: FundingRadar::RelevanceScorer.new,
      reports_dir: dir,
      filename: filename,
      llm_processor: llm_processor,
      processing_mode: processing_mode
    )
  end
end
