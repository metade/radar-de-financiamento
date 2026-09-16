require "date"
require "digest"
require "fileutils"
require "json"
require "time"

module FundingRadar
  module StaticApi
    VERSION = "1".freeze
    PREFIX = "/api/v1".freeze

    module Id
      module_function

      def for(value)
        raw = value.to_s.strip
        normalized = raw.downcase.gsub(/[^a-z0-9._~-]+/, "-").gsub(/\A-+|-+\z/, "")
        normalized = "opportunity-#{Digest::SHA256.hexdigest(raw)[0, 16]}" if normalized.empty?
        normalized
      end
    end

    class Builder
      attr_reader :records

      def initialize(reports:, generated_at: Time.now.utc.iso8601)
        @reports = reports
        @generated_at = generated_at
        @records = latest_records
      end

      def write(destination)
        api_root = File.join(destination, PREFIX.delete_prefix("/"))
        opportunities_root = File.join(api_root, "opportunities")
        FileUtils.rm_rf(opportunities_root)
        FileUtils.mkdir_p(opportunities_root)

        write_json(File.join(api_root, "meta.json"), meta)
        write_json(File.join(api_root, "catalog.json"), catalog)
        write_json(File.join(api_root, "schema.json"), self.class.schema)
        @records.each_value do |record|
          write_json(File.join(opportunities_root, "#{record.fetch("id")}.json"), public_record(record))
        end
      end

      def meta
        {
          "api_version" => VERSION,
          "generated_at" => @generated_at,
          "opportunity_count" => @records.size,
          "catalog_count" => catalog.size,
          "catalog_url" => "#{PREFIX}/catalog.json",
          "schema_url" => "#{PREFIX}/schema.json",
          "detail_url_template" => "#{PREFIX}/opportunities/{id}.json"
        }
      end

      def catalog
        @records.values
          .select { |record| %w[open unknown].include?(record.fetch("status")) }
          .sort_by { |record| [record.fetch("deadline", "9999-12-31"), record.fetch("title")] }
          .map { |record| catalog_record(record) }
      end

      def self.schema
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$id" => "/api/v1/schema.json",
          "title" => "Funding Radar opportunity",
          "type" => "object",
          "required" => %w[id title programme status facts analysis provenance links],
          "properties" => {
            "id" => {"type" => "string", "pattern" => "^[a-z0-9][a-z0-9._~-]*$"},
            "source_reference_id" => {"type" => "string"},
            "title" => {"type" => "string"},
            "programme" => {"type" => "string"},
            "status" => {"type" => "string", "enum" => %w[open closed unknown]},
            "facts" => {"$ref" => "#/$defs/facts"},
            "analysis" => {"$ref" => "#/$defs/analysis"},
            "provenance" => {"$ref" => "#/$defs/provenance"},
            "links" => {"$ref" => "#/$defs/links"}
          },
          "$defs" => {
            "facts" => {
              "type" => "object",
              "properties" => {
                "opening_date" => {"type" => ["string", "null"], "format" => "date"},
                "deadline" => {"type" => ["string", "null"], "format" => "date"},
                "funding_amount" => {"type" => "string"},
                "eligible_applicants" => {"type" => "array", "items" => {"type" => "string"}},
                "partnership_requirements" => {"type" => "string"},
                "other_requirements" => {"type" => "string"},
                "themes" => {"type" => "array", "items" => {"type" => "string"}}
              },
              "additionalProperties" => false
            },
            "analysis" => {
              "type" => "object",
              "required" => ["summary"],
              "properties" => {
                "summary" => {"type" => "string"},
                "relevance_score" => {"type" => "integer"},
                "relevance_category" => {"type" => "string"},
                "relevance_explanation" => {"type" => "string"},
                "llm_analysis" => {"type" => "object"}
              },
              "additionalProperties" => false
            },
            "provenance" => {
              "type" => "object",
              "required" => %w[source_reference_id report_generated_at],
              "properties" => {
                "source_organisation" => {"type" => "string"},
                "source_reference_id" => {"type" => "string"},
                "report_generated_at" => {"type" => "string", "format" => "date-time"},
                "opening_date_source" => {"type" => "string"},
                "deadline_source" => {"type" => "string"}
              },
              "additionalProperties" => false
            },
            "links" => {
              "type" => "object",
              "properties" => {
                "source_url" => {"type" => "string", "format" => "uri"},
                "document_url" => {"type" => "string", "format" => "uri"}
              },
              "additionalProperties" => false
            }
          },
          "additionalProperties" => false
        }
      end

      private

      def latest_records
        latest = {}
        @reports.each do |report|
          report_data = report.respond_to?(:data) ? report.data : report
          report_generated_at = report_data["generated_at"].to_s
          Array(report_data["opportunities"]).each do |item|
            next if item["id"].to_s.strip.empty?

            api_id = Id.for(item["id"])
            next if latest.key?(api_id) && latest[api_id].fetch("_report_generated_at") >= report_generated_at

            latest[api_id] = detail_record(item, report_generated_at, api_id)
          end
        end
        latest
      end

      def detail_record(item, report_generated_at, api_id)
        record = {
          "id" => api_id,
          "title" => item.fetch("title").to_s,
          "programme" => item.fetch("programme").to_s,
          "status" => status_for(item["deadline"]),
          "facts" => compact({
            "opening_date" => item["opening_date"],
            "deadline" => item["deadline"],
            "funding_amount" => item["funding_amount"],
            "eligible_applicants" => item["eligible_applicants"],
            "partnership_requirements" => item["partnership_requirements"],
            "other_requirements" => item["other_requirements"],
            "themes" => item["themes"]
          }),
          "analysis" => compact({
            "summary" => item["summary"],
            "relevance_score" => item["relevance_score"],
            "relevance_category" => item["relevance_category"],
            "relevance_explanation" => item["relevance_explanation"],
            "llm_analysis" => item["llm_analysis"]
          }),
          "provenance" => compact({
            "source_organisation" => item["funding_source"],
            "source_reference_id" => item["id"],
            "report_generated_at" => report_generated_at,
            "opening_date_source" => item["opening_date_source"],
            "deadline_source" => item["deadline_source"]
          }),
          "links" => compact({
            "source_url" => item["official_link"],
            "document_url" => item["document_link"]
          })
        }
        record["source_reference_id"] = item["id"].to_s unless api_id == item["id"].to_s
        record["_report_generated_at"] = report_generated_at
        record
      end

      def catalog_record(record)
        facts = record.fetch("facts")
        analysis = record.fetch("analysis")
        compact({
          "id" => record.fetch("id"),
          "title" => record.fetch("title"),
          "programme" => record.fetch("programme"),
          "source" => record.dig("provenance", "source_organisation"),
          "deadline" => facts["deadline"],
          "status" => record.fetch("status"),
          "applicants" => facts["eligible_applicants"],
          "themes" => facts["themes"],
          "summary" => analysis["summary"],
          "detail_url" => "#{PREFIX}/opportunities/#{record.fetch("id")}.json",
          "source_url" => record.dig("links", "source_url")
        })
      end

      def status_for(deadline)
        return "unknown" if deadline.to_s.strip.empty?

        Date.iso8601(deadline.to_s) < Date.today ? "closed" : "open"
      rescue Date::Error
        "unknown"
      end

      def compact(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            compacted = compact(item)
            result[key] = compacted unless compacted.nil? || compacted == "" || compacted == []
          end
        when Array
          value.map { |item| compact(item) }.reject { |item| item.nil? || item == "" }
        else
          value
        end
      end

      def write_json(path, value)
        File.write(path, JSON.pretty_generate(value) + "\n")
      end

      def public_record(record)
        record.reject { |key, _value| key == "_report_generated_at" }
      end
    end
  end
end
