require "cgi"
require "date"
require "uri"

module FundingRadar
  module Sources
    class EuropeanUrbanInitiativeSource
      CATALOGUE_URL = "https://portico.urban-initiative.eu/urban-panorama/call-for-proposals".freeze
      FUNDING_SOURCE = "European Urban Initiative".freeze
      PROGRAMME = "European Urban Initiative".freeze

      THEME_PATTERNS = {
        "climate" => /climate|green|nature|energy|resilien|sustainable/i,
        "community_development" => /urban|city|cities|local|territorial|community/i,
        "digital_public_services" => /digital|smart city|data|technology/i,
        "environment" => /environment|circular|water|biodiversity|nature/i,
        "inclusion" => /inclus|social|housing|just and inclusive/i,
        "mobility" => /mobilit|transport/i,
        "public_space" => /public space|urban development|place-based/i
      }.freeze

      def initialize(http_client:, catalogue_url: CATALOGUE_URL)
        @http_client = http_client
        @catalogue_url = catalogue_url
      end

      def fetch
        html = @http_client.get(@catalogue_url, headers: {"Accept" => "text/html"})
        extract_cards(html).filter_map { |card| normalize(card) }
      rescue StandardError
        []
      end

      private

      def extract_cards(html)
        article_html = html.to_s.scan(/<article\b.*?<\/article>/im)
        call_cards = article_html.select { |card| card.match?(/node--type-call-for-proposals/i) }
        cards = (call_cards.empty? ? article_html : call_cards).map { |card| parse_card(card) }
        return cards unless cards.empty?

        # Keep the parser useful with the simpler card fragments used by mirrors
        # and tests, where the catalogue may omit the article wrapper.
        html.to_s.split(/(?=<h[1-6]\b)/i).filter_map do |fragment|
          next unless fragment.match?(/\b(?:Open|Upcoming|Closed)\b/i)

          parse_card(fragment.split(/(?=<h[1-6]\b)/i, 2).first)
        end
      end

      def parse_card(html)
        text = plain_text(html)
        title = plain_text(html.match(/class=["'][^"']*title-node[^"']*["'][^>]*>(.*?)<\/[^>]+>/im)&.captures&.first)
        title = tag_text(html) if title.empty?
        link = html.scan(/<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/im).map do |href, label|
          [href, plain_text(label)]
        end.reverse.find { |_href, label| label.match?(/find out more|learn more|details/i) }&.first
        partner_link = html.scan(/<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/im).find do |_href, label|
          plain_text(label).match?(/\bBy\b/i)
        end&.first

        {
          text: text,
          title: title,
          link: link,
          partner_link: partner_link,
          status: text[/\b(Open|Upcoming|Closed)\b/i],
          deadline: text[/Deadline date\s*:\s*(\d{1,2}\/\d{1,2}\/\d{4})/i, 1],
          amount: text[/Funding support\s*:\s*(.+?)(?=\s+(?:Find out more|Support\s*:|$))/i, 1],
          applicants: text[/\b(Urban authorities|Municipalities[^.]*|Local\/regional authorities[^.]*|Public authorities[^.]*)/i, 1]
        }
      end

      def normalize(card)
        return if card[:title].to_s.empty? || card[:status].to_s.casecmp("Closed").zero?

        title = card[:title]
        Opportunity.from_hash(
          "id" => "eui-#{slug(title)}",
          "title" => title,
          "programme" => PROGRAMME,
          "opening_date" => nil,
          "deadline" => parse_date(card[:deadline]),
          "funding_amount" => euro_amount(card[:amount]),
          "funding_source" => FUNDING_SOURCE,
          "official_link" => preferred_link(card),
          "eligible_applicants" => eligible_applicants(card[:applicants], card[:text]),
          "partnership_requirements" => partnership_requirements(card[:text]),
          "other_requirements" => [card[:status], support(card[:text])].compact.join(" · "),
          "summary" => summary(card[:text]),
          "themes" => themes_for([title, card[:text]].join(" "))
        )
      end

      def tag_text(html, _tag = nil)
        match = html.match(/<(h[1-6])\b[^>]*>(.*?)<\/\1>/im)
        plain_text(match && match[2])
      end

      def plain_text(html)
        raw = html.to_s.dup.force_encoding("UTF-8")
        text = CGI.unescapeHTML(raw).encode("UTF-8", invalid: :replace, undef: :replace)
        text.gsub(/<script\b.*?<\/script>/im, "").gsub(/<style\b.*?<\/style>/im, "").gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end

      def parse_date(value)
        Date.strptime(value.to_s, "%d/%m/%Y").iso8601 if value
      rescue Date::Error
        nil
      end

      def euro_amount(value)
        if value.to_s.match?(/million/i)
          millions = value.to_s[/[\d,.]+/].to_s.tr(",", "").to_f
          return "€#{(millions * 1_000_000).to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}" if millions.positive?
        end

        digits = value.to_s.gsub(/\D/, "")
        return "" if digits.empty? || digits.to_i.zero?

        "€#{digits.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end

      def absolute_link(link)
        return @catalogue_url if link.to_s.empty?
        return link if link.start_with?("http")

        URI.join(@catalogue_url, link).to_s
      rescue URI::InvalidURIError
        @catalogue_url
      end

      def preferred_link(card)
        link = card[:link]
        link = card[:partner_link] if link.to_s.match?(/\.pdf(?:\?|\z)/i)
        absolute_link(link)
      end

      def eligible_applicants(value, text)
        value = text[/\b(Urban authorities|Municipalities[^.]*|Local\/regional authorities[^.]*)/i, 1] if value.to_s.empty?
        [value].compact.reject(&:empty?)
      end

      def partnership_requirements(text)
        "Confirm partnership requirements in the official call." if text.match?(/partners?|consorti|together|cohort/i)
      end

      def support(text)
        text[/Support\s*:\s*([^·]+?)(?=\s+Funding support:|\z)/i, 1]&.strip
      end

      def summary(text)
        text.sub(/\A.*?\b(?:Open|Upcoming|Closed)\b\s*/i, "").split(/\s+(?:Support|Funding support|Find out more)\s*:/i).first.to_s.strip
      end

      def themes_for(text)
        THEME_PATTERNS.filter_map { |theme, pattern| theme if text.match?(pattern) }
      end

      def slug(value)
        value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")[0, 80]
      end
    end
  end
end
