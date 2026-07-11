require "cgi"
require "date"
require "uri"

module FundingRadar
  module Sources
    class InterregSudoeSource
      INDEX_URL = "https://interreg-sudoe.eu/en/las-convocatorias-sudoe-ya-estan-abiertas/call/".freeze
      CALENDAR_URL = "https://interreg-sudoe.eu/en/calendario-de-convocatorias/".freeze
      NEXT_CALLS_URL = "https://interreg-sudoe.eu/en/next-calls/".freeze
      CALL_URLS = ["https://interreg-sudoe.eu/en/3rd-call/", "https://interreg-sudoe.eu/en/4th-call/"].freeze
      FUNDING_SOURCE = "Interreg Sudoe".freeze
      PROGRAMME = "Interreg Sudoe".freeze
      REQUEST_HEADERS = {
        "Accept" => "text/html,application/xhtml+xml",
        "User-Agent" => "Mozilla/5.0 (compatible; EU Funding Radar; +https://github.com/)"
      }.freeze
      MONTHS = {
        "january" => 1, "february" => 2, "march" => 3, "april" => 4,
        "may" => 5, "june" => 6, "july" => 7, "august" => 8,
        "september" => 9, "october" => 10, "november" => 11, "december" => 12
      }.freeze
      THEME_PATTERNS = {
        "climate" => /climate|wildfire|forest|water|environment|resilien/i,
        "community_development" => /territor|local authorit|public polic|cooperation/i,
        "digital_public_services" => /digital|innovation|technology/i,
        "environment" => /water|wildfire|forest|environment|ecosystem/i,
        "inclusion" => /ageing|aging|health|social|population/i,
        "public_space" => /urban|local authorit|territor/i
      }.freeze

      def initialize(http_client:, index_url: INDEX_URL, call_urls: CALL_URLS, discovery_urls: nil)
        @http_client = http_client
        @index_url = index_url
        @call_urls = call_urls
        @discovery_urls = discovery_urls || [index_url, CALENDAR_URL, NEXT_CALLS_URL]
      end

      def fetch
        pages = @discovery_urls.filter_map do |url|
          @http_client.get(url, headers: REQUEST_HEADERS)
        rescue StandardError => error
          warn "Interreg Sudoe discovery error for #{url}: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
          nil
        end
        index = plain_text(pages.first.to_s)
        links = discover_links(pages.join("\n"))
        links = @call_urls if links.empty?

        links.uniq.filter_map do |link|
          page_url = URI.join(@index_url, link).to_s
          html = @http_client.get(page_url, headers: REQUEST_HEADERS)
          normalize(html, page_url, index)
        rescue StandardError => error
          warn "Interreg Sudoe parse error for #{link}: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
          nil
        end
      rescue StandardError => error
        warn "Interreg Sudoe fetch error: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
        []
      end

      private

      def discover_links(html)
        html.to_s.scan(/<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/im).filter_map do |href, label|
          url = URI.join(@index_url, CGI.unescapeHTML(href)).to_s
          path = URI(url).path.to_s
          next unless path.match?(/call|convocatoria/i)
          next if path.match?(/calendar|calendario|next-calls|results|call-for-tenders|submitting|news|noticias|category|publicacion|futuras|future|webinar|programmes?|las-convocatorias/i)

          url
        rescue URI::InvalidURIError
          nil
        end
      end

      def normalize(html, link, index)
        text = plain_text(html)
        title = page_title(html)
        return if title.empty? || title.match?(/results|closed/i)

        title = title.sub(/\s*\((?:open|upcoming|closed)\)/i, "")
        deadline = labeled_date(text, /deadline|closure|closing/i) || labeled_date(index, /deadline|closure|closing/i)
        opening = labeled_date(text, /call open|opening|opened/i) || labeled_date(index, /call open|opening|opened/i)
        dates = index.scan(/\d{1,2}\s+[a-z]+\s+\d{4}/i)
        opening ||= parse_date(dates.first)
        deadline ||= parse_date(dates[1])
        amount = text[/Call budget.*?(?:ERDF budget amounts|Available ERDF funding)\s+€?\s*([\d\s.,]+)/im, 1]

        Opportunity.from_hash(
          "id" => "sudoe-#{slug(title)}",
          "title" => title,
          "programme" => PROGRAMME,
          "opening_date" => opening,
          "deadline" => deadline,
          "funding_amount" => euro_amount(amount),
          "funding_source" => FUNDING_SOURCE,
          "official_link" => link,
          "eligible_applicants" => ["Entidades públicas", "Entidades privadas sem fins lucrativos"],
          "partnership_requirements" => "Parceria transnacional com pelo menos um beneficiário de Portugal, Espanha e França; confirmar os requisitos no aviso oficial.",
          "other_requirements" => "Financiamento FEDER até 75%; candidatura em parceria transnacional.",
          "summary" => summary(text),
          "themes" => themes_for(text)
        )
      end

      def page_title(html)
        title = html.to_s[/<title\b[^>]*>(.*?)<\/title>/im, 1].to_s
        title = CGI.unescapeHTML(title).sub(/\s+-\s+Interreg Sudoe.*\z/i, "").strip
        title = plain_text(html[/<h1\b[^>]*>(.*?)<\/h1>/im, 1]) if title.empty?
        title = plain_text(html)[/\b(?:\d+(?:st|nd|rd|th)|priority|iso|valorisation)[^.!?]{0,100}\bcall\b/i].to_s if title.empty?
        title
      end

      def labeled_date(text, label)
        parse_date(text[/#{label}.{0,160}?((?:\d{1,2}\s+[a-z]+\s+\d{4})|(?:\d{1,2}[\/-]\d{1,2}[\/-]\d{4}))/i, 1])
      end

      def plain_text(html)
        raw = html.to_s.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
        CGI.unescapeHTML(raw.gsub(/<script\b.*?<\/script>|<style\b.*?<\/style>/im, "").gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      end

      def parse_date(value)
        match = value.to_s.match(/(\d{1,2})\s+([a-z]+)\s+(\d{4})/i)
        return Date.strptime(value.to_s, "%d/%m/%Y").iso8601 unless match
        return unless MONTHS[match[2].downcase]

        Date.new(match[3].to_i, MONTHS[match[2].downcase], match[1].to_i).iso8601
      rescue Date::Error
        nil
      end

      def slug(value)
        value.to_s.downcase.encode("ASCII", invalid: :replace, undef: :replace, replace: "")
          .gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\z-/, "")[0, 80]
      end

      def euro_amount(value)
        digits = value.to_s.gsub(/[^\d]/, "")
        return "" if digits.empty? || digits.to_i.zero?

        "€#{digits.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end

      def summary(text)
        candidates = text.scan(/(?:Launch of the \d+(?:st|nd|rd|th) Interreg Sudoe call|Taking action against wildfires and population ageing).*?(?=\s+(?:What is|What are|Who can|Call budget|Would you like))/i)
        candidates.max_by(&:length).to_s.strip
      end

      def themes_for(text)
        THEME_PATTERNS.filter_map { |theme, pattern| theme if text.match?(pattern) }
      end
    end
  end
end
