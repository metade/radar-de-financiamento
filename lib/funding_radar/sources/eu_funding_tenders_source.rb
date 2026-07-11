require "cgi"
require "date"
require "json"

module FundingRadar
  module Sources
    class EuFundingTendersSource
      ENDPOINT = "https://api.tech.ec.europa.eu/search-api/prod/rest/search".freeze
      TOPIC_INDEX_URL = "https://ec.europa.eu/info/funding-tenders/opportunities/data/topic-list.html".freeze
      PORTAL_TOPIC_PATH = "/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/".freeze
      DATA_TOPIC_PATH = "/info/funding-tenders/opportunities/data/topicDetails/".freeze
      PROGRAMME_PREFIXES = {
        "AMIF" => "AMIF",
        "CEF" => "Connecting Europe Facility",
        "CERV" => "CERV",
        "CREA" => "Europa Criativa",
        "DIGITAL" => "Europa Digital",
        "ERASMUS" => "Erasmus+",
        "EU4H" => "EU4Health",
        "HORIZON" => "Horizon Europe",
        "LIFE" => "LIFE",
        "SMP" => "Single Market Programme",
        "UCPM" => "Union Civil Protection Mechanism"
      }.freeze
      DISCOVERY_PREFIXES = PROGRAMME_PREFIXES.keys.freeze

      THEME_PATTERNS = {
        "accessibility" => [/\baccessibility\b/, /\baccessible\b/, /\bdisabilit(?:y|ies)\b/],
        "civic_participation" => [/\bcitizen participation\b/, /\bpublic participation\b/, /\bdemocrac(?:y|ies)\b/, /\bdemocratic\b/],
        "climate" => [/\bclimate\b/, /\badaptation\b/, /\bresilience\b/],
        "community_development" => [/\blocal authorities\b/, /\blocal communities\b/, /\bmunicipal(?:ities)?\b/, /\bcities\b/, /\bregional development\b/, /\bneighbou?rhoods?\b/],
        "digital_public_services" => [/\bdigital public services\b/, /\bpublic services\b/, /\binteroperability\b/, /\be-government\b/, /\bsmart cit(?:y|ies)\b/],
        "environment" => [/\benvironment(?:al)?\b/, /\bbiodiversity\b/, /\bnature\b/, /\bpollution\b/],
        "equality" => [/\bequality\b/, /\bfundamental rights\b/, /\bnon-discrimination\b/],
        "inclusion" => [/\binclusion\b/, /\bsocial inclusion\b/, /\bintegration\b/],
        "mobility" => [/\bmobility\b/, /\btransport\b/, /\burban mobility\b/],
        "public_space" => [/\bpublic spaces?\b/, /\burban\b/, /\bneighbou?rhoods?\b/],
        "volunteering" => [/\bvolunteer(?:ing)?\b/]
      }.freeze
      LOCAL_AUTHORITY_PATTERNS = [
        /\bmunicipal(?:ities)?\b/,
        /\bcities\b/,
        /\blocal authorit(?:y|ies)\b/
      ].freeze
      PUBLIC_BODY_PATTERNS = [
        /\bpublic authorit(?:y|ies)\b/,
        /\bpublic bod(?:y|ies)\b/,
        /\bpublic entit(?:y|ies)\b/
      ].freeze
      PARTNERSHIP_PATTERNS = [
        /\bconsorti(?:um|a)\b/,
        /\bpartners?\b/,
        /\bpartnerships?\b/,
        /\btransnational\b/
      ].freeze

      def initialize(http_client:, endpoint: ENDPOINT, topic_index_url: TOPIC_INDEX_URL, terms: nil, topic_ids: nil, page_size: 10, max_topic_ids: 40, current_year: Date.today.year)
        @http_client = http_client
        @endpoint = endpoint
        @topic_index_url = topic_index_url
        @terms = terms || self.class.default_terms(current_year: current_year)
        @topic_ids = topic_ids
        @page_size = page_size
        @max_topic_ids = max_topic_ids
        @current_year = current_year
      end

      def fetch
        seed_results = search_terms.flat_map { |term| fetch_term(term) }
        exact_topic_results = extract_topic_ids(seed_results).flat_map { |topic_id| fetch_term(topic_id) }
        topic_candidates = seed_results + exact_topic_results
        enrichment_results = enrichment_terms_for(topic_candidates).flat_map { |term| fetch_term(term) }

        best_topic_results(topic_candidates + enrichment_results)
          .reject { |result| closed?(result.fetch("metadata", {})) }
          .map { |result| normalize(result) }
          .compact
      end

      def self.discoverable_topic_id?(topic_id, current_year: Date.today.year)
        relevant_year = topic_id.match?(/(?:\A|-)(#{current_year}|#{current_year + 1})(?:-|\z)/)
        relevant_prefix = DISCOVERY_PREFIXES.any? { |prefix| topic_id.start_with?(prefix) }
        relevant_year && relevant_prefix
      end

      def self.default_terms(current_year: Date.today.year)
        years = [current_year, current_year + 1]
        stems = [
          "CERV",
          "CREA-CROSS",
          "CREA-CULT",
          "DIGITAL",
          "ERASMUS-SPORT",
          "HORIZON-CL3",
          "HORIZON-CL6",
          "HORIZON-MISS",
          "HORIZON-NEB",
          "LIFE"
        ]

        years.flat_map { |year| stems.map { |stem| "#{stem}-#{year}" } }
      end

      private

      def search_terms
        discovered = @topic_ids || discover_topic_ids
        return discovered unless discovered.empty?

        @terms
      end

      def discover_topic_ids
        body = @http_client.get(@topic_index_url, headers: {"Accept" => "text/html"})
        body.scan(%r{/topic-details/([^"<>]+)}i)
          .flatten
          .map { |id| CGI.unescapeHTML(id).upcase }
          .select { |id| discoverable_topic_id?(id) }
          .uniq
          .first(@max_topic_ids)
      rescue StandardError
        []
      end

      def discoverable_topic_id?(topic_id)
        self.class.discoverable_topic_id?(topic_id, current_year: @current_year)
      end

      def fetch_term(term)
        url = "#{@endpoint}?apiKey=SEDIA&text=#{CGI.escape(term)}&pageSize=#{@page_size}&pageNumber=1"
        JSON.parse(@http_client.post_json(url, headers: {"Accept" => "application/json"})).fetch("results", [])
      rescue JSON::ParserError, KeyError, StandardError
        []
      end

      def best_topic_results(results)
        results
          .select { |result| topic_result?(result) }
          .group_by { |result| topic_id_for(result) }
          .values
          .map { |group| group.max_by { |result| topic_result_quality(result) } }
      end

      def enrichment_terms_for(results)
        results
          .select { |result| topic_result?(result) }
          .select { |result| thin_topic_result?(result) }
          .uniq { |result| topic_id_for(result) }
          .first(@max_topic_ids)
          .filter_map { |result| title_for(result) }
      end

      def topic_result?(result)
        url = result.fetch("url", "")
        return false unless url.include?(PORTAL_TOPIC_PATH) || url.include?(DATA_TOPIC_PATH)

        topic_id = topic_id_for(result)
        !topic_id.empty? && self.class.discoverable_topic_id?(topic_id, current_year: @current_year)
      end

      def topic_result_quality(result)
        metadata = result.fetch("metadata", {})
        [
          deadline_for(metadata) ? 1 : 0,
          metadata.key?("actions") ? 1 : 0,
          metadata.key?("status") || metadata.key?("sortStatus") ? 1 : 0,
          result.fetch("url", "").end_with?(".json") ? 0 : 1,
          metadata.keys.size
        ]
      end

      def thin_topic_result?(result)
        metadata = result.fetch("metadata", {})
        !deadline_for(metadata) && !metadata.key?("actions") && !metadata.key?("status") && !metadata.key?("sortStatus")
      end

      def normalize(result)
        metadata = result.fetch("metadata", {})
        topic_id = topic_id_for(result)
        title = title_for(result)

        return nil if topic_id.empty? || title.empty?

        Opportunity.from_hash(
          "id" => "eu-ft-#{topic_id.downcase}",
          "title" => title,
          "programme" => programme_for(topic_id, metadata),
          "deadline" => deadline_for(metadata),
          "funding_source" => "EU Funding & Tenders Portal",
          "official_link" => official_link_for(topic_id),
          "eligible_applicants" => eligible_applicants_for(result, metadata),
          "partnership_requirements" => partnership_requirements_for(result, metadata),
          "summary" => summary_for(result),
          "themes" => themes_for(result, metadata)
        )
      end

      def topic_id_for(result)
        metadata = result.fetch("metadata", {})
        url_topic = result.fetch("url", "").split(PORTAL_TOPIC_PATH, 2).last.to_s
        url_topic = result.fetch("url", "").split(DATA_TOPIC_PATH, 2).last.to_s.delete_suffix(".json") if url_topic == result.fetch("url", "")
        clean(first_present(metadata_value(metadata, "identifier"), url_topic, result["reference"])).delete_suffix(".json").upcase
      end

      def title_for(result)
        metadata = result.fetch("metadata", {})
        clean(first_present(
          metadata_value(metadata, "title", "esST_title", "esST_Title", "identifier"),
          result["title"],
          result["content"],
          topic_id_for(result)
        ))
      end

      def official_link_for(topic_id)
        "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/#{topic_id.downcase}"
      end

      def programme_for(topic_id, metadata)
        explicit = clean(metadata_value(metadata, "programme", "esST_programmeName", "esST_programme"))
        return explicit unless explicit.empty? || explicit.match?(/\A\d+\z/)

        PROGRAMME_PREFIXES.each do |prefix, name|
          return name if topic_id.upcase.start_with?(prefix)
        end

        topic_id.split("-").first.to_s
      end

      def deadline_for(metadata)
        value = metadata_value(metadata, "deadlineDate", "callDeadlineDate", "esDA_deadlineDate", "esST_deadlineDate", "deadline")
        value ||= deadline_from_actions(metadata_value(metadata, "actions"))
        parse_date(value)
      end

      def eligible_applicants_for(result, metadata)
        text = searchable_text(result, metadata)
        applicants = []
        applicants << "Municípios ou autoridades locais" if LOCAL_AUTHORITY_PATTERNS.any? { |pattern| text.match?(pattern) }
        applicants << "Entidades públicas" if PUBLIC_BODY_PATTERNS.any? { |pattern| text.match?(pattern) }
        applicants.uniq
      end

      def partnership_requirements_for(result, metadata)
        text = searchable_text(result, metadata)
        return "O texto da oportunidade indica requisitos de consórcio ou parceria; confirmar no aviso oficial." if PARTNERSHIP_PATTERNS.any? { |pattern| text.match?(pattern) }

        "Confirmar requisitos de parceria no aviso oficial."
      end

      def summary_for(result)
        summary = clean(first_present(result["summary"], result["content"]))
        return summary unless summary.empty?

        "Oportunidade publicada no portal EU Funding & Tenders. Consultar a página oficial para confirmar âmbito, elegibilidade e documentação."
      end

      def themes_for(result, metadata)
        text = searchable_text(result, metadata)
        THEME_PATTERNS.each_with_object([]) do |(theme, patterns), themes|
          themes << theme if patterns.any? { |pattern| text.match?(pattern) }
        end
      end

      def searchable_text(result, metadata)
        [
          result["summary"],
          result["content"],
          searchable_metadata_values(metadata)
        ].flatten.compact.join(" ").downcase
      end

      def searchable_metadata_values(metadata)
        metadata.reject { |key, _value| key.to_s.match?(/\A(?:url|esST_URL|links?|supportInfo)\z/i) }.values.flatten
      end

      def extract_topic_ids(results)
        regex = /\b(?:#{DISCOVERY_PREFIXES.join("|")})-[A-Z0-9-]*(?:#{@current_year}|#{@current_year + 1})[A-Z0-9-]*\b/i
        results.flat_map do |result|
          metadata = result.fetch("metadata", {})
          searchable_text(result, metadata).scan(regex)
        end.map(&:upcase).uniq.first(@max_topic_ids)
      end

      def metadata_value(metadata, *keys)
        keys.each do |key|
          next unless metadata.key?(key)

          value = Array(metadata[key]).compact.first
          return value unless value.to_s.strip.empty?
        end
        nil
      end

      def closed?(metadata)
        text = [
          metadata_value(metadata, "status"),
          metadata_value(metadata, "sortStatus"),
          metadata_value(metadata, "actions")
        ].compact.join(" ").downcase

        text.include?("closed") || text.include?("31094503")
      end

      def deadline_from_actions(value)
        return nil if value.to_s.strip.empty?

        actions = JSON.parse(value)
        Array(actions).lazy
          .flat_map { |action| Array(action["deadlineDates"]) }
          .find { |deadline| !deadline.to_s.strip.empty? }
      rescue JSON::ParserError, TypeError
        nil
      end

      def first_present(*values)
        values.find { |value| !value.to_s.strip.empty? }.to_s
      end

      def clean(value)
        value.to_s
          .gsub(/<[^>]*>/, " ")
          .gsub(/\s+/, " ")
          .strip
      end

      def parse_date(value)
        return nil if value.to_s.strip.empty?

        text = value.to_s.strip
        return Time.at(text.to_i / 1000).utc.to_date.iso8601 if text.match?(/\A\d{12,}\z/)
        return Date.iso8601(text[0, 10]).iso8601 if text.match?(/\A\d{4}-\d{2}-\d{2}/)

        nil
      rescue Date::Error, ArgumentError
        nil
      end
    end
  end
end
