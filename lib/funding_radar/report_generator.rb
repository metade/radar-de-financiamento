require "date"
require "csv"
require "fileutils"
require "time"
require "yaml"

module FundingRadar
  class ReportGenerator
    DISCLAIMER = "A elegibilidade deve ser sempre confirmada nos avisos e documentação oficial de cada programa.".freeze

    def initialize(source_registry:, duplicate_resolver:, scorer:, reports_dir:, filename: nil, llm_processor: nil, processing_mode: "deterministic")
      @source_registry = source_registry
      @duplicate_resolver = duplicate_resolver
      @scorer = scorer
      @reports_dir = reports_dir
      @filename = filename
      @llm_processor = llm_processor
      @processing_mode = processing_mode
    end

    def generate(today: Date.today, tenders_per_source: nil)
      opportunities = limit_per_source(@source_registry.fetch_all, tenders_per_source)
      opportunities = @duplicate_resolver.resolve(opportunities)
      scored_pairs = opportunities.map { |opportunity| [opportunity, @scorer.score(opportunity, today: today)] }
      scored_pairs.sort_by! { |opportunity, result| [-result.score, opportunity.deadline.to_s, opportunity.title] }

      deterministic = scored_pairs.map { |opportunity, result| serialize(opportunity, result, today) }
      processed = process(scored_pairs)
      scored = processed.map do |opportunity, result|
        serialize(opportunity, result, today, llm_result: @processing_results&.fetch(opportunity.id))
      end
      if comparison_mode?
        scored.each_with_index { |item, index| item["deterministic_summary"] = deterministic[index].fetch("summary") }
      end

      report = Report.new(
        week_id: iso_week_id(today),
        title: "Radar semanal de financiamento - #{iso_week_label(today)}",
        generated_on: today.iso8601,
        generated_at: Time.now.getlocal.iso8601,
        opportunities: scored
      )

      FileUtils.mkdir_p(@reports_dir)
      filename = @filename || "#{report.week_id}.md"
      path = File.join(@reports_dir, filename)
      File.write(path, render(report))
      File.write(csv_path_for(filename), render_csv(report))
      path
    end

    private

    def limit_per_source(opportunities, limit)
      return opportunities if limit.nil?

      limit = Integer(limit)
      raise ArgumentError, "tenders_per_source must be greater than zero" unless limit.positive?

      counts = Hash.new(0)
      opportunities.select do |opportunity|
        source = opportunity.funding_source.to_s
        next false if counts[source] >= limit

        counts[source] += 1
        true
      end
    rescue ArgumentError
      raise ArgumentError, "tenders_per_source must be a positive integer"
    end

    def serialize(opportunity, result, today, llm_result: nil)
      item = {
        "id" => opportunity.id,
        "title" => opportunity.title,
        "programme" => opportunity.programme,
        "opening_date" => opportunity.opening_date,
        "deadline" => opportunity.deadline,
        "funding_amount" => opportunity.funding_amount,
        "funding_source" => opportunity.funding_source,
        "official_link" => opportunity.official_link,
        "eligible_applicants" => opportunity.eligible_applicants,
        "partnership_requirements" => opportunity.partnership_requirements,
        "other_requirements" => opportunity.other_requirements,
        "summary" => opportunity.summary,
        "themes" => opportunity.themes,
        "relevance_score" => result.score,
        "relevance_category" => result.category,
        "relevance_explanation" => result.explanation,
        "deadline_status" => deadline_status(opportunity, today)
      }
      item["llm_analysis"] = llm_result.analysis if llm_result&.analysis
      item
    end

    def process(scored_pairs)
      return scored_pairs if @processing_mode == "deterministic" || !@llm_processor

      @processing_results = {}
      scored_pairs.map do |opportunity, result|
        processed = @llm_processor.process(opportunity)
        @processing_results[opportunity.id] = processed
        processed_opportunity = opportunity.with(
          summary: processed.summary,
          themes: @processing_mode == "source_config" ? processed.themes : opportunity.themes
        )
        [processed_opportunity, result]
      end
    end

    def comparison_mode?
      @processing_mode == "both" && @llm_processor
    end

    def render(report)
      front_matter = {
        "layout" => "report",
        "title" => report.title,
        "week_id" => report.week_id,
        "generated_on" => report.generated_on,
        "generated_at" => report.generated_at,
        "disclaimer" => DISCLAIMER,
        "opportunities" => report.opportunities
      }
      front_matter["comparison"] = true if comparison_mode?

      "#{front_matter.to_yaml}---\n"
    end

    def render_csv(report)
      CSV.generate(headers: true) do |csv|
        csv << csv_headers
        report.opportunities.each do |opportunity|
          csv << csv_headers.map { |header| csv_value(opportunity.fetch(header)) }
        end
      end
    end

    def csv_headers
      %w[
        id title programme opening_date deadline funding_amount funding_source official_link eligible_applicants
        partnership_requirements other_requirements summary themes relevance_score relevance_category
        relevance_explanation deadline_status
      ]
    end

    def csv_value(value)
      return value.join("; ") if value.is_a?(Array)

      value
    end

    def csv_path_for(filename)
      File.join(@reports_dir, "#{File.basename(filename, ".md")}.csv")
    end

    def iso_week_id(date)
      "#{date.cwyear}-W#{date.cweek.to_s.rjust(2, "0")}"
    end

    def iso_week_label(date)
      "semana #{date.cweek} de #{date.cwyear}"
    end

    def deadline_status(opportunity, today)
      deadline = opportunity.deadline_date
      return "Prazo por confirmar" unless deadline

      days = (deadline - today).to_i
      return "Prazo ultrapassado" if days.negative?
      return "Prazo muito próximo" if days <= 21
      return "Prazo próximo" if days <= 60

      "Prazo com margem"
    end
  end
end
