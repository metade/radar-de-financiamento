require "test_helper"

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
      assert_operator document.fetch("opportunities").size, :>=, 1
      assert document.fetch("opportunities").first.key?("relevance_score")
      assert document.fetch("opportunities").first.key?("deadline_status")
      assert document.fetch("disclaimer").include?("documentação oficial")
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

  private

  def build_generator(dir)
    source = FundingRadar::Sources::FixtureSource.new(path: File.expand_path("../data/sources/fixtures.yml", __dir__))
    FundingRadar::ReportGenerator.new(
      source_registry: FundingRadar::SourceRegistry.new(sources: [source]),
      duplicate_resolver: FundingRadar::DuplicateResolver.new,
      scorer: FundingRadar::RelevanceScorer.new,
      reports_dir: dir
    )
  end
end
