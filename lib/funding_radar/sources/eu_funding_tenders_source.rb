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

      def initialize(http_client:, endpoint: ENDPOINT, topic_index_url: TOPIC_INDEX_URL, terms: nil, topic_ids: nil, page_size: 10, max_topic_ids: 40, current_year: Date.today.year, single_topic: false)
        @http_client = http_client
        @endpoint = endpoint
        @topic_index_url = topic_index_url
        @terms = terms || self.class.default_terms(current_year: current_year)
        @topic_ids = topic_ids
        @page_size = page_size
        @max_topic_ids = max_topic_ids
        @current_year = current_year
        @single_topic = single_topic
      end

      def fetch
        seed_results = search_terms.flat_map { |term| fetch_term(term) }
        exact_topic_results = extract_topic_ids(seed_results).flat_map { |topic_id| fetch_term(topic_id) }
        topic_candidates = seed_results + exact_topic_results
        enrichment_results = enrichment_terms_for(topic_candidates).flat_map { |term| fetch_term(term) }

        best_topic_results(topic_candidates + enrichment_results)
          .compact
          .select { |result| !@single_topic || @topic_ids.include?(topic_id_for(result)) }
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
      rescue StandardError => error
        Debug.log "EU Funding & Tenders topic discovery failed: #{error.class}: #{error.message}; using default search terms"
        []
      end

      def discoverable_topic_id?(topic_id)
        self.class.discoverable_topic_id?(topic_id, current_year: @current_year)
      end

      def fetch_term(term)
        query = exact_topic_query?(term) ? %Q{"#{term}"} : term
        url = "#{@endpoint}?apiKey=SEDIA&text=#{CGI.escape(query)}&pageSize=#{@page_size}&pageNumber=1&language=en"
        JSON.parse(@http_client.post_json(url, headers: {"Accept" => "application/json"})).fetch("results", [])
      rescue StandardError => error
        Debug.log "EU Funding & Tenders search failed for #{term.inspect}: #{error.class}: #{error.message}"
        []
      end

      def exact_topic_query?(term)
        term.to_s.match?(/\A(?:#{DISCOVERY_PREFIXES.join("|")})-[A-Z0-9]+(?:-[A-Z0-9]+){3,}\z/i)
      end

      def best_topic_results(results)
        results
          .select { |result| topic_result?(result) }
          .group_by { |result| topic_id_for(result) }
          .values
          .map do |group|
            selected = group.max_by { |result| topic_result_quality(result) }
            english = group.find { |result| language_for(result.fetch("metadata", {})) == "en" }
            if english.nil?
              next group.select { |result| language_for(result.fetch("metadata", {})).empty? }
                .max_by { |result| topic_result_quality(result) }
            end

            next selected if language_for(selected.fetch("metadata", {})) == "en"

            metadata = selected.fetch("metadata", {}).merge(
              "title" => metadata_value(english.fetch("metadata", {}), "title", "esST_title"),
              "language" => ["en"]
            )
            selected.merge(
              "metadata" => metadata,
              "title" => english["title"],
              "summary" => english["summary"],
              "content" => english["content"]
            )
          end
      end

      def enrichment_terms_for(results)
        results
          .select { |result| topic_result?(result) }
          .select { |result| thin_topic_result?(result) }
          .sort_by { |result| @single_topic && @topic_ids.include?(topic_id_for(result)) ? 0 : 1 }
          .uniq { |result| topic_id_for(result) }
          .first(@max_topic_ids)
          .flat_map do |result|
            metadata = result.fetch("metadata", {})
            title = title_for(result)
            [
              title,
              title.sub(/\s*\([^)]*\)\z/, ""),
              metadata_value(metadata, "callIdentifier")
            ].compact
          end
          .reject(&:empty?)
          .uniq
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
          language_for(metadata) == "en" ? 1 : 0,
          metadata.keys.size
        ]
      end

      def language_for(metadata)
        metadata_value(metadata, "language", "lang").to_s.downcase.split(/[-_]/).first.to_s
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
          "opening_date" => opening_date_for(metadata),
          "deadline" => deadline_for(metadata),
          "funding_amount" => funding_amount_for(result, metadata),
          "funding_source" => "EU Funding & Tenders Portal",
          "official_link" => official_link_for(topic_id),
          "eligible_applicants" => eligible_applicants_for(result, metadata),
          "partnership_requirements" => partnership_requirements_for(result, metadata),
          "other_requirements" => other_requirements_for(result, metadata),
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
        value ||= deadline_from_metadata(metadata)
        parse_date(value)
      end

      def opening_date_for(metadata)
        value = metadata_value(metadata, "openingDate", "callOpeningDate", "startDate", "esDA_startDate", "esST_startDate", "start")
        parse_date(value)
      end

      def funding_amount_for(result, metadata)
        preferred_keys = %w[
          fundingAmount grantAmount maxGrantAmount budget estimatedBudget
          euContribution maximumGrantAmount esDA_budget esDA_maxGrantAmount
        ]
        preferred_keys.each do |key|
          candidate = metadata_value(metadata, key)
          normalized = normalize_funding_amount(candidate, metadata)
          return normalized if normalized
        end

        topic_budget = topic_budget_from_metadata(metadata, topic_id_for(result))
        return topic_budget if topic_budget

        nested_candidate = budget_value_from_metadata(metadata)
        return nested_candidate if nested_candidate

        funding_amount_from_text(searchable_text(result, metadata))
      end

      def normalize_funding_amount(value, metadata)
        return nil if value.nil?

        if value.is_a?(Hash)
          amount = first_present(value["amount"], value[:amount], value["value"], value[:value])
          currency = first_present(value["currency"], value[:currency], "EUR")
          return format_funding_amount(amount, currency) if amount_numeric?(amount)
        end

        return nil if value.is_a?(Hash) || value.is_a?(Array)

        text = clean(value)
        return nil unless text.match?(/\d/)

        text.gsub(/\bEUR\b/i, "€")
      end

      def budget_value_from_metadata(value, key = nil)
        if value.is_a?(Hash)
          amount = value.each_with_object({}) { |(child_key, child_value), found| found[child_key.to_s.downcase] = child_value }
          amount_value = amount.values_at("amount", "value", "budget", "fundingamount", "grantamount", "maxgrantamount").compact.first
          currency = amount.values_at("currency", "currencycode").compact.first || "EUR"
          return format_funding_amount(amount_value, currency) if amount_numeric?(amount_value)

          value.each do |child_key, child_value|
            next unless child_key.to_s.match?(/budget|funding|grant|contribution|amount/i)

            candidate = budget_value_from_metadata(child_value, child_key)
            return candidate if candidate
          end
        elsif value.is_a?(Array)
          value.each do |child_value|
            candidate = budget_value_from_metadata(child_value, key)
            return candidate if candidate
          end
        elsif key.to_s.match?(/\A(?:budget|fundingamount|grantamount|maxgrantamount|eucontribution|maximumgrantamount)\z/i)
          return normalize_funding_amount(value, {})
        end

        nil
      end

      def topic_budget_from_metadata(metadata, topic_id)
        maps = []
        collect_metadata_values(metadata, "budgetTopicActionMap", maps)
        maps.each do |map|
          map = parse_json_value(map) || map
          actions = map.values.flatten.select { |action| action.is_a?(Hash) }
          action = actions.find { |candidate| candidate["action"].to_s.upcase.start_with?(topic_id) }
          next unless action

          total = action.fetch("budgetYearMap", {}).values.sum { |amount| numeric_amount(amount) }
          maximum = numeric_amount(action["maxContribution"])
          next if total.zero? && maximum.zero?

          parts = []
          parts << "€#{format_integer(total)} total" unless total.zero?
          parts << "até €#{format_integer(maximum)}/projeto" unless maximum.zero?
          return parts.join("; ")
        end

        nil
      end

      def collect_metadata_values(value, target_key, found)
        if value.is_a?(String)
          parsed = parse_json_value(value)
          return collect_metadata_values(parsed, target_key, found) if parsed
        end

        if value.is_a?(Hash)
          value.each do |key, child_value|
            found << child_value if key.to_s.casecmp(target_key).zero?
            collect_metadata_values(child_value, target_key, found)
          end
        elsif value.is_a?(Array)
          value.each { |child_value| collect_metadata_values(child_value, target_key, found) }
        end
      end

      def numeric_amount(value)
        return 0 unless value.to_s.match?(/\A\d+(?:\.\d+)?\z/)

        value.to_f
      end

      def format_integer(value)
        value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      def funding_amount_from_text(text)
        matches = text.scan(/(?:€|EUR)\s*\d[\d\s.,]*(?:\s*(?:million|billion|milhões|milhão|m|bn|b))?|\d[\d\s.,]*(?:\s*(?:million|billion|milhões|milhão|m|bn|b))?\s*(?:EUR|€)/i)
        matches.map(&:strip).reject { |match| match.match?(/\A(?:EUR|€)[,.]?\z/i) }.max_by(&:length)
      end

      def amount_numeric?(value)
        value.to_s.match?(/\d/)
      end

      def format_funding_amount(amount, currency)
        return nil unless amount_numeric?(amount)

        formatted_amount = if amount.to_s.match?(/\A\d+\z/)
          amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        else
          clean(amount)
        end

        currency_label = clean(currency).sub(/\AEUR\z/i, "€")
        "#{currency_label} #{formatted_amount}".strip
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

        nil
      end

      def other_requirements_for(result, metadata)
        value = metadata_value(metadata, "requirements", "eligibilityConditions", "conditions", "esIN_requirements", "esIN_eligibility")
        return clean(value) unless value.to_s.strip.empty?
        nil
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

      def deadline_from_metadata(metadata)
        deadline_values(metadata).lazy.map { |value| parse_date(value) }.find(&:itself)
      end

      def deadline_values(value, key = nil)
        if value.is_a?(Hash)
          value.flat_map { |child_key, child_value| deadline_values(child_value, child_key) }
        elsif value.is_a?(Array)
          value.flat_map { |child_value| deadline_values(child_value, key) }
        elsif key.to_s.match?(/deadline/i)
          parsed = parse_json_value(value)
          parsed ? deadline_values(parsed, key) : [value]
        elsif key.to_s.casecmp("actions").zero?
          parsed = parse_json_value(value)
          parsed ? deadline_values(parsed) : []
        else
          []
        end
      end

      def parse_json_value(value)
        return value if value.is_a?(Hash) || value.is_a?(Array)
        return nil unless value.is_a?(String) && value.lstrip.match?(/[\[{]/)

        JSON.parse(value)
      rescue JSON::ParserError
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
