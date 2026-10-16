require "date"
require "nokogiri"
require "uri"

module FundingRadar
  module Sources
    class EdpSolidariaSource
      INDEX_URL = "https://www.fundacaoedp.pt/pt/edp-solidaria".freeze
      PROGRAMME = "EDP Energia Solidária".freeze
      REQUEST_HEADERS = {"Accept" => "text/html,application/xhtml+xml"}.freeze
      MONTHS = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze
      DATE_PATTERN = /\d{1,2}(?:\s+de\s+[a-zç]+(?:\s+de\s+\d{4})?|[\/-]\d{1,2}[\/-]\d{4})/i
      CLOSED_PATTERN = /candidaturas?\s+(?:encerrad|fechad)|vencedores\s+(?:foram|j[aá])|resultados\s+(?:publicad|divulgad)|edi[cç][aã]o\s+encerrad/i

      def initialize(http_client:, index_url: INDEX_URL, today: Date.today)
        @http_client = http_client
        @index_url = index_url
        @today = today
      end

      def fetch
        page = document(@http_client.get(@index_url, headers: REQUEST_HEADERS))
        heading = page.css("h1, h2, h3").find { |node| text(node).match?(/\AEdi[cç][aã]o\s+20\d{2}/i) }
        return [] unless heading

        edition = text(heading).scan(/20\d{2}/).uniq
        # Scope status and summary to this edition, excluding programme history
        # and the supported-project archive below it.
        section = heading.ancestors("section").first || heading.parent
        description = text(section)
        return [] if description.match?(CLOSED_PATTERN)

        rules_link = page.css("a[href]").find { |node| text(node).match?(/\ARegulamento\z/i) }
        rules_url = absolute_link(rules_link&.[]("href"))
        rules = fetch_rules(rules_url, edition)
        phase_one = rules.css("li, p").map { |node| text(node) }.find { |value| value.match?(/candidaturas simplificadas\s*\(fase 1\)/i) }
        dates = phase_one.to_s.scan(DATE_PATTERN)
        year = dates.last.to_s[/20\d{2}/]
        opening = parse_date(dates[0], year)
        deadline = parse_date(dates[1], year)
        # Phase 2 is invitation-only: its deadline must never extend the
        # opportunity for new applicants past the phase 1 deadline.
        return [] if deadline && Date.iso8601(deadline) < @today
        return [] unless deadline || description.match?(/candidaturas?\s+abertas?|abertura\s+(?:de\s+)?candidaturas?/i)

        paragraphs = rules.css("p").map { |node| text(node) }
        eligibility = rules.css("li").map { |node| text(node) }.select { |value| value.match?(/\A(?:ou\s+)?(?:entidades\s+)?(?:sem|com) fins lucrativos/i) }
        restrictions = paragraphs.select { |value| value.match?(/organismos p[uú]blicos.*n[aã]o podem apresentar candidaturas/i) }
        requirements = paragraphs.select { |value| value.match?(/legalmente constitu[ií]das h[aá]|s[oó] s[aã]o aceites projetos.*territ[oó]rio nacional/i) }
        amount = paragraphs.find { |value| value.match?(/valor global do apoio.*por cada projeto/i) }.to_s
        amounts = amount.scan(/\d[\d.,]*\s*€/).map(&:strip)

        [Opportunity.from_hash(
          "id" => "edp-solidaria-#{edition.join('-')}",
          "title" => "#{PROGRAMME} — Edição #{edition.join('–')}",
          "programme" => PROGRAMME,
          "opening_date" => opening,
          "deadline" => deadline,
          "funding_amount" => amounts.empty? ? "" : "#{amounts.join(' a ')} por projeto",
          "funding_source" => "Fundação EDP",
          "source_key" => "edp_solidaria",
          "official_link" => @index_url,
          "document_link" => rules_url,
          "eligible_applicants" => eligibility,
          "partnership_requirements" => restrictions.join(" "),
          "other_requirements" => requirements.join(" "),
          "summary" => section.css("p").map { |node| text(node) }.reject(&:empty?).join(" "),
          "themes" => themes_for(description),
          "geography" => paragraphs.any? { |value| value.match?(/s[oó] s[aã]o aceites projetos.*territ[oó]rio nacional/i) } ? {"scope" => "national", "areas" => ["Portugal"]} : nil
        )]
      rescue StandardError => error
        warn "EDP Solidária fetch error: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
        []
      end

      private

      def fetch_rules(url, edition)
        return document("") if url.empty? || URI(url).path.end_with?(".pdf")

        rules = document(@http_client.get(url, headers: REQUEST_HEADERS))
        # The programme page can announce a new edition while still linking
        # the previous edition's FAQ. Do not reuse those facts.
        rule_years = rules.css("a").select { |node| text(node).match?(/regulamento/i) }.flat_map { |node| text(node).scan(/20\d{2}/) }
        return document("") unless rule_years.include?(edition.first)

        rules
      rescue StandardError => error
        warn "EDP Solidária rules error: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
        document("")
      end

      def document(html)
        doc = Nokogiri::HTML(html.to_s.dup.force_encoding("UTF-8"))
        doc.css("script, style, nav, footer").remove
        doc.at_css("article") || doc.at_css("main") || doc
      end

      def text(node)
        node.to_s.empty? ? "" : node.text.gsub(/[\s\u00a0\u200b-\u200d\ufeff]+/, " ").strip
      end

      def parse_date(value, fallback_year)
        return if value.to_s.empty?

        if value.include?(" de ")
          day, month, year = value.downcase.split(" de ")
          return unless (year || fallback_year).to_s.match?(/\A20\d{2}\z/)

          Date.new((year || fallback_year).to_i, MONTHS.index(month).to_i + 1, day.to_i).iso8601 if MONTHS.include?(month)
        else
          Date.strptime(value.tr("-", "/"), "%d/%m/%Y").iso8601
        end
      rescue Date::Error
        nil
      end

      def absolute_link(href)
        return "" if href.to_s.empty?

        uri = URI.join(@index_url, href)
        %w[http https].include?(uri.scheme) ? uri.to_s : ""
      rescue URI::InvalidURIError
        ""
      end

      def themes_for(description)
        {
          "climate" => /energ|clim[aá]t|descarbon/i,
          "inclusion" => /social|inclus|vulnerab/i,
          "environment" => /patrim[oó]nio natural|circular|vida selvagem|biodivers/i,
          "mobility" => /mobilidade/i
        }.filter_map { |theme, pattern| theme if description.match?(pattern) }
      end
    end
  end
end
