require "cgi"
require "date"
require "uri"

module FundingRadar
  module Sources
    class TurismoDePortugalSource
      LISTING_URL = "https://business.turismodeportugal.pt/pt/Investir/Financiamento/avisos-concursos/Paginas/default.aspx".freeze
      FUNDING_SOURCE = "Turismo de Portugal".freeze
      PROGRAMME = "Turismo de Portugal".freeze
      REQUEST_HEADERS = {"Accept" => "text/html,application/xhtml+xml"}.freeze

      THEME_PATTERNS = {
        "climate" => /climat|descarbon|efici[eê]ncia energ[eé]tica|energia|sustent|ambiente|res[ií]du/i,
        "community_development" => /territ[oó]rio|interior|regional|local|cidade|comunidade/i,
        "digital_public_services" => /digital|tecnolog|inova[cç][aã]o/i,
        "environment" => /ambiente|biodivers|descarbon|energia|sustent/i,
        "inclusion" => /inclus|acessib|social|igualdade/i,
        "mobility" => /mobilidade|transporte/i,
        "public_space" => /regenera[cç][aã]o|reabilita[cç][aã]o|territ[oó]rio|urbana/i
      }.freeze

      def initialize(http_client:, listing_url: LISTING_URL)
        @http_client = http_client
        @listing_url = listing_url
      end

      def fetch
        listing = @http_client.get(@listing_url, headers: REQUEST_HEADERS)
        extract_cards(listing).filter_map do |card|
          detail = card[:link].to_s.empty? ? "" : @http_client.get(card[:link], headers: REQUEST_HEADERS)
          normalize(card, detail)
        rescue StandardError => error
          warn "Turismo de Portugal parse error for #{card[:link]}: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
          normalize(card, "")
        end
      rescue StandardError => error
        warn "Turismo de Portugal fetch error: #{error.class}: #{error.message}" if ENV["FUNDING_RADAR_DEBUG"] == "true"
        []
      end

      private

      def extract_cards(html)
        links = html.to_s.scan(/<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/im)
        links.filter_map do |href, label|
          title = plain_text(label)
          next if title.empty? || !title.match?(/(?:aviso|call|candidatur|fundo|registo|linha|concurso)/i)
          next if title.match?(/encerrad|suspens|closed/i)

          url = absolute_link(href)
          next if same_page?(url) || url.match?(/candidaturas-avisos-concurso-encerrados/i)
          next unless listing_directory_link?(url)
          next if title.match?(/\A(?:avisos? de concursos?|candidatura|linhas? de financiamento|candidaturas? a pr[eé]mios)\z/i)

          {title: title, link: url, listing_text: title}
        end.uniq { |card| card[:link] }
      end

      def normalize(card, detail_html)
        text = plain_text([card[:listing_text], detail_html].join(" "))
        return if text.empty? || text.match?(/candidaturas?\s+(?:j[aá]\s+)?encerrad|candidaturas suspens/i)

        title = card[:title].sub(/\s*-\s*candidaturas?\s+(?:a decorrer|at[eé].*)\z/i, "").strip
        return if private_only?(text) || duplicate_portugal2030_notice?(title)

        Opportunity.from_hash(
          "id" => "turismo-#{slug(card[:link].empty? ? title : card[:link])}",
          "title" => title,
          "programme" => PROGRAMME,
          "opening_date" => labeled_date(text, /in[ií]cio|abertura|a partir de/i),
          "deadline" => labeled_date(text, /prazo|candidaturas? at[eé]|data limite|encerramento|limite/i),
          "funding_amount" => euro_amount(text),
          "funding_source" => FUNDING_SOURCE,
          "official_link" => card[:link],
          "eligible_applicants" => eligible_applicants(text),
          "partnership_requirements" => partnership_requirements(text),
          "other_requirements" => other_requirements(text),
          "summary" => summary(text),
          "themes" => themes_for(text)
        )
      end

      def plain_text(html)
        raw = html.to_s.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
        CGI.unescapeHTML(raw.gsub(/<script\b.*?<\/script>|<style\b.*?<\/style>/im, "").gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      end

      def labeled_date(text, label)
        value = text[/#{label}.{0,140}?((?:\d{1,2}\s+de?\s+[a-zç]+\s+de?\s+\d{4})|(?:\d{1,2}[\/-]\d{1,2}[\/-]\d{4})|(?:\d{1,2}\s+[a-zç]+\s+\d{4}))/i, 1]
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
        applicants << "Entidades públicas" if text.match?(/entidades? p[uú]blic|munic[ií]p|autarqu/i)
        applicants << "Entidades privadas" if text.match?(/empresas?|entidades? privadas?|PME|promotor/i)
        applicants
      end

      def private_only?(text)
        private_signal = text.match?(/\b(?:empresas?|PME|entidades? privadas?|promotor(?:es)?|sociedade[s]?)\b/i)
        public_signal = text.match?(/\b(?:entidades? p[uú]blicas?|munic[ií]pios?|autarquias?|cidades?|administra[cç][aã]o p[uú]blica)\b/i)
        private_signal && !public_signal && text.match?(/(?:destinat[aá]ri|benefici[aá]ri|elegib|podem candidatar|proponent)/i)
      end

      def duplicate_portugal2030_notice?(title)
        title.match?(/Portugal\s*2030|SICE\b|Pedido\s+Aux[ií]lio|Inova[cç][aã]o\s+Produtiva/i)
      end

      def partnership_requirements(text)
        "Confirmar os requisitos de parceria no aviso oficial." if text.match?(/parceria|cons[oó]rcio|consortium|joint/i)
      end

      def other_requirements(text)
        text[/((?:candidaturas?|submiss[aã]o).{0,180})/i, 1].to_s.strip
      end

      def summary(text)
        text[/\A.*?(?=\s+(?:Per[ií]odo|Prazo|Benefici[aá]rios?|Candidaturas?))/i].to_s.strip
      end

      def themes_for(text)
        THEME_PATTERNS.filter_map { |theme, pattern| theme if text.match?(pattern) }
      end

      def absolute_link(link)
        return @listing_url if link.to_s.empty?
        URI.join(@listing_url, CGI.unescapeHTML(link)).to_s
      rescue URI::InvalidURIError
        @listing_url
      end

      def same_page?(url)
        URI(url).tap { |uri| uri.fragment = nil }.to_s == URI(@listing_url).tap { |uri| uri.fragment = nil }.to_s
      rescue URI::InvalidURIError
        true
      end

      def listing_directory_link?(url)
        listing_path = URI(@listing_url).path.to_s
        return true unless listing_path.match?(/\/default\.aspx\z/i)

        URI(url).path.to_s.start_with?(listing_path.sub(%r{/default\.aspx\z}i, "/"))
      rescue URI::InvalidURIError
        false
      end

      def slug(value)
        value.to_s.downcase.encode("ASCII", invalid: :replace, undef: :replace, replace: "").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\z-/, "")[0, 80]
      end
    end
  end
end
