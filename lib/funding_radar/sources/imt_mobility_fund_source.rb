require "cgi"
require "date"
require "nokogiri"
require "uri"

module FundingRadar
  module Sources
    class ImtMobilityFundSource
      INDEX_URL = "https://www.imt-ip.pt/fundo-mobilidade-e-transportes/avisos-de-candidatura/".freeze
      FUNDING_SOURCE = "Fundo para a Mobilidade e Transportes (IMT)".freeze
      PROGRAMME = "Fundo para a Mobilidade e Transportes".freeze
      REQUEST_HEADERS = {"Accept" => "text/html,application/xhtml+xml"}.freeze

      THEME_PATTERNS = {
        "climate" => /descarbon|energia|sustent|ambient|emiss[aã]o/i,
        "community_development" => /autoridades? de transport|mobilidade escolar|territ[oó]rio|urbana/i,
        "digital_public_services" => /digital|bilh[eé]tica|informa[cç][aã]o|tecnolog/i,
        "environment" => /ambient|sustent|emiss[aã]o/i,
        "inclusion" => /acessib|inclus|social/i,
        "mobility" => /mobilidade|transport|t[aá]xi|biciclet/i,
        "public_space" => /parag|esta[cç][aã]o|urbana/i
      }.freeze

      def initialize(http_client:, index_url: INDEX_URL)
        @http_client = http_client
        @index_url = index_url
      end

      def fetch
        index = @http_client.get(@index_url, headers: REQUEST_HEADERS)
        year_pages(index).filter_map do |year_page|
          html = @http_client.get(year_page[:link], headers: REQUEST_HEADERS)
          notice_cards(html, year_page[:year]).filter_map do |card|
            detail = @http_client.get(card[:link], headers: REQUEST_HEADERS)
            normalize(card, detail)
          rescue StandardError => error
            warn "IMT notice parse error for #{card[:link]}: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
            normalize(card, "")
          end
        rescue StandardError => error
          warn "IMT year page fetch error for #{year_page[:link]}: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
          []
        end.flatten
      rescue StandardError => error
        warn "IMT fetch error: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
        []
      end

      private

      def year_pages(html)
        doc = Nokogiri::HTML(utf8(html))
        allowed_years = [Date.today.year, Date.today.year - 1].map(&:to_s)
        pages = doc.css("a").filter_map do |anchor|
          year = plain_text([anchor.text, anchor["href"]].join(" "))[/\b(20\d{2})\b/, 1]
          next unless allowed_years.include?(year)

          {year: year, link: absolute_link(anchor["href"])}
        end
        pages = pages.reject { |page| page[:link].empty? }
        return pages.uniq { |page| page[:link] } unless pages.empty?

        # The IMT index has used accordion-like year headings, and some
        # responses omit the year anchors entirely. Keep the conventional
        # WordPress year URL as a fallback so discovery still works.
        years = allowed_years
        years.map do |year|
          {year: year, link: absolute_link("avisos-de-candidatura-#{year}/")}
        end
      end

      def notice_cards(html, year)
        doc = Nokogiri::HTML(utf8(html))
        doc.css("h1, h2, h3, h4, h5, h6").filter_map do |heading|
          title = plain_text(heading.text)
          next unless title.match?(/\bAviso\b/i)

          anchor = heading.at_css("a") || heading.previous_element&.at_css("a")
          link = absolute_link(anchor && anchor["href"])
          next if link == @index_url || link.empty?

          {title: title, link: link, year: year}
        end.uniq { |card| card[:link] }
      end

      def normalize(card, detail_html)
        detail = utf8(detail_html)
        text = plain_text([card[:title], detail].join(" "))
        return if text.empty? || text.match?(/candidaturas?\s+encerrad|aviso\s+encerrad|\bencerrad[oa]s?\b|\bclosed\b/i)

        deadline = labeled_date(text, /prazo|data limite|encerramento|submiss[aã]o.*?at[eé]/i)
        return if deadline && Date.iso8601(deadline) < Date.today

        title = card[:title].sub(/\s+-\s+candidaturas?.*\z/i, "").strip
        Opportunity.from_hash(
          "id" => "imt-mobility-#{slug(card[:link].empty? ? title : card[:link])}",
          "title" => title,
          "programme" => PROGRAMME,
          "opening_date" => labeled_date(text, /in[ií]cio|abertura|a partir de/i),
          "deadline" => deadline,
          "funding_amount" => euro_amount(text),
          "funding_source" => FUNDING_SOURCE,
          "source_key" => "imt_mobility_fund",
          "official_link" => card[:link],
          "document_link" => pdf_link(detail_html),
          "eligible_applicants" => eligible_applicants(text),
          "partnership_requirements" => partnership_requirements(text),
          "other_requirements" => other_requirements(text),
          "summary" => summary(text),
          "themes" => themes_for(text)
        )
      end

      def utf8(html)
        html.to_s.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
      end

      def plain_text(html)
        CGI.unescapeHTML(utf8(html).gsub(/<script\b.*?<\/script>|<style\b.*?<\/style>/im, "").gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      end

      def labeled_date(text, label)
        value = text[/#{label}.{0,180}?((?:\d{1,2}\s+de?\s+[a-zç]+\s+de?\s+\d{4})|(?:\d{1,2}[\/-]\d{1,2}[\/-]\d{4})|(?:\d{1,2}\s+[a-zç]+\s+\d{4}))/i, 1]
        parse_date(value)
      end

      def parse_date(value)
        return if value.to_s.empty?

        cleaned = value.to_s.gsub(/\s+de\s+/i, " ").gsub(/\s+/, " ").strip
        Date.strptime(cleaned, "%d/%m/%Y").iso8601 rescue Date.parse(cleaned).iso8601
      rescue Date::Error
        nil
      end

      def euro_amount(text)
        values = text.scan(/(?:€\s*|EUR\s*)([\d\s.,]+)|([\d\s.,]+)\s*(?:€|euros?)/i).flatten.compact
        number = values.map { |value| value.gsub(/\s/, "").gsub(/\.(?=\d{3}(?:\D|$))/, "").tr(",", ".") }.map { |value| Float(value, exception: false) }.compact.max
        return "" unless number && number.positive?

        "€#{number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end

      def eligible_applicants(text)
        applicants = []
        applicants << "Entidades públicas" if text.match?(/entidades? p[uú]blic|munic[ií]p|autarqu|autoridades? de transport/i)
        applicants << "Entidades privadas" if text.match?(/empresas?|entidades? privadas?|operadores?|promotor/i)
        applicants
      end

      def partnership_requirements(text)
        "Confirmar os requisitos de parceria no aviso oficial." if text.match?(/parceria|cons[oó]rcio/i)
      end

      def other_requirements(text)
        text[/((?:benefici[aá]ri|destinat[aá]ri|candidaturas?|submiss[aã]o).{0,220})/i, 1].to_s.strip
      end

      def summary(text)
        text[/\A.*?(?=\s+(?:Data|Prazo|Benefici[aá]rios?|Candidaturas?))/i].to_s.strip
      end

      def themes_for(text)
        THEME_PATTERNS.filter_map { |theme, pattern| theme if text.match?(pattern) }
      end

      def pdf_link(html)
        href = Nokogiri::HTML(utf8(html)).css("a[href]").find { |anchor| anchor["href"].match?(/\.pdf(?:\?|\z)/i) }&.[]("href")
        absolute_link(href)
      end

      def absolute_link(link)
        return "" if link.to_s.empty?

        URI.join(@index_url, CGI.unescapeHTML(link)).to_s
      rescue URI::InvalidURIError
        ""
      end

      def slug(value)
        value.to_s.downcase.encode("ASCII", invalid: :replace, undef: :replace, replace: "").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")[0, 90]
      end
    end
  end
end
