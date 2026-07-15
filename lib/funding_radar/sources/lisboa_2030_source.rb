require "date"
require "json"
require "nokogiri"
require "uri"

module FundingRadar
  module Sources
    class Lisboa2030Source
      QUERY_URL = "https://lisboa.portugal2030.pt/wp-json/avisos/query".freeze
      AVISOS_URL = "https://lisboa.portugal2030.pt/avisos/".freeze
      PROGRAMME_ID = 105
      OPEN_STATUS_ID = 7
      FUNDING_SOURCE = "Portugal 2030".freeze
      SOURCE_KEY = "lisboa_2030".freeze
      PROGRAMME = "LISBOA2030".freeze

      THEME_PATTERNS = {
        "climate" => /climat|ambient|energia|resilien|sustent/i,
        "community_development" => /territorial|comunidade|urbana|munic|cidade|coesão|lisboa/i,
        "digital_public_services" => /digital|tecnolog|inovação|inteligente/i,
        "environment" => /ambient|resídu|água|sustent/i,
        "inclusion" => /inclus|social|qualifica|emprego|demograf/i,
        "mobility" => /mobilidade|metro|ferrovi|transporte/i,
        "public_space" => /urbana|territorial|reabilitação/i
      }.freeze

      def initialize(http_client:, query_url: QUERY_URL)
        @http_client = http_client
        @query_url = query_url
      end

      def fetch
        records = []
        0.upto(20) do |page|
          payload = JSON.parse(@http_client.post_form(@query_url, form: {estadoAvisoId: OPEN_STATUS_ID, programaId: PROGRAMME_ID, page: page}, headers: {"Accept" => "application/json"}))
          page_records = Array(payload["avisos"])
          records.concat(page_records)
          break if page_records.length < 5
        end
        records.filter_map { |record| normalize_safely(record) }
      rescue StandardError => error
        Debug.failure "Lisboa2030Source failed: #{error.class}: #{error.message}"
        []
      end

      private

      def normalize_safely(record)
        normalize(record)
      rescue StandardError => error
        Debug.failure "Lisboa2030Source skipped malformed record: #{error.class}: #{error.message}"
        nil
      end

      def normalize(record)
        notice = record.fetch("aviso")
        code = notice["codigoAviso"].to_s.strip
        return unless code.match?(/\ALISBOA2030-\d{4}-\d+\z/i)

        structure = Array(record["estrutura"]).find { |entry| entry["programaOperacionalId"].to_i == PROGRAMME_ID }
        calendar = record.fetch("calendario", {})
        title = plain_text(notice["designacaoPT"] || notice["designacaoEN"])
        return if title.empty?

        text = [title, structure&.values].flatten.compact.join(" ")
        Opportunity.from_hash(
          "id" => "lisboa2030-#{code.downcase.delete_prefix("lisboa2030-")}",
          "title" => title,
          "programme" => PROGRAMME,
          "opening_date" => date_value(calendar["dataInicio"]),
          "deadline" => date_value(calendar["dataFimAtual"] || calendar["dataFim"]),
          "funding_amount" => euro_amount(structure && structure["dotacao"]),
          "funding_source" => FUNDING_SOURCE,
          "source_key" => SOURCE_KEY,
          "official_link" => official_link(code),
          "document_link" => document_link(record),
          "eligible_applicants" => eligible_applicants(text),
          "partnership_requirements" => text.match?(/parceria|consórcio/i) ? "Confirmar os requisitos de parceria no aviso oficial." : nil,
          "other_requirements" => code,
          "summary" => "Aviso Lisboa 2030: #{title}. Consultar o aviso oficial para confirmar condições, documentação e candidatura.",
          "themes" => themes_for(text)
        )
      end

      def date_value(value)
        Date.parse(value.to_s).iso8601 if value
      rescue Date::Error
        nil
      end

      def official_link(code)
        "#{AVISOS_URL}#aviso-#{code.downcase}"
      end

      def document_link(record)
        document = Array(record["documentos"]).find do |item|
          item["tipoDocumentoDesignacao"].to_s.match?(/aviso/i) || item["documentoDesignacao"].to_s.match?(/\.pdf\z/i)
        end
        return "#{@query_url.sub(%r{/query\z}, "/download")}?#{URI.encode_www_form(container: document["container"], path: document["path"])}" if document && document["container"] && document["path"]

        ""
      end

      def plain_text(value)
        Nokogiri::HTML.fragment(value.to_s).text.gsub(/\s+/, " ").strip
      end

      def euro_amount(value)
        number = Float(value, exception: false)
        return "" if number.nil? || number.zero?

        "€#{number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end

      def eligible_applicants(text)
        applicants = []
        applicants << "Entidades públicas" if text.match?(/públic|municí|autarqui/i)
        applicants << "Entidades privadas" if text.match?(/privad|empresa/i)
        applicants
      end

      def themes_for(text)
        THEME_PATTERNS.filter_map { |theme, pattern| theme if text.match?(pattern) }
      end
    end
  end
end
