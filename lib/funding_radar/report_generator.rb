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

    def generate(today: Date.today)
      opportunities = @duplicate_resolver.resolve(@source_registry.fetch_all)
      scored_pairs = opportunities.map { |opportunity| [opportunity, @scorer.score(opportunity, today: today)] }
      scored_pairs.sort_by! { |opportunity, result| [-result.score, opportunity.deadline.to_s, opportunity.title] }

      deterministic = scored_pairs.map { |opportunity, result| serialize(opportunity, result, today) }
      processed = process(scored_pairs)
      scored = processed.map { |opportunity, result| serialize(opportunity, result, today) }

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
      write_comparison(scored_pairs, deterministic, processed, report.week_id, filename, today) if @processing_mode == "both" && @llm_processor
      path
    end

    private

    def serialize(opportunity, result, today)
      {
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
    end

    def process(scored_pairs)
      return scored_pairs if @processing_mode == "deterministic" || !@llm_processor

      @processing_results = {}
      scored_pairs.map do |opportunity, result|
        processed = @llm_processor.process(opportunity)
        @processing_results[opportunity.object_id] = processed
        [opportunity.with(summary: processed.summary), result]
      end
    end

    def write_comparison(scored_pairs, deterministic, processed, week_id, filename, today)
      comparison_filename = "#{File.basename(filename, ".md")}-llm-comparison.md"
      comparison_path = File.join(@reports_dir, comparison_filename)
      rows = scored_pairs.each_with_index.map do |(opportunity, result), index|
        llm_opportunity, = processed[index]
        llm_result = @processing_results.fetch(opportunity.object_id)
        [deterministic[index], llm_opportunity, llm_result]
      end

      content = [
        {"layout" => "default", "title" => "Comparação LLM - #{week_id}", "week_id" => week_id}.to_yaml.sub(/\A---\n/, ""),
        "---",
        "\n# Comparação entre resumo determinístico e resumo LLM\n",
        "Gerado em #{Time.now.getlocal.iso8601}. A versão determinística continua a ser a referência.\n"
      ]
      rows.each do |deterministic_item, llm_opportunity, llm_result|
        content << "## #{deterministic_item.fetch("title")}\n"
        content << "**Fonte:** #{deterministic_item.fetch("funding_source")}  \n"
        content << "**Ligação oficial:** #{deterministic_item.fetch("official_link")}  \n"
        content << "\n**Resumo determinístico**\n\n#{markdown_text(deterministic_item.fetch("summary"))}\n"
        content << "\n**Resumo LLM (#{llm_result.status})**\n\n#{markdown_text(llm_opportunity.summary)}\n"
        content << "\n---\n"
      end
      File.write(comparison_path, content.join("\n"))
    end

    def markdown_text(value)
      value.to_s.gsub("\n", " ")
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
