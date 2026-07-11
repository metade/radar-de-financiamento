require "date"
require "uri"
require_relative "../xlsx_reader"

module FundingRadar
  module Sources
    class Portugal2030Source
      WORKBOOK_URL = "https://portugal2030.pt/wp-content/uploads/sites/3/2026/05/PlanoAnualAvisos_download_052026.xlsx".freeze
      PLAN_URL = "https://portugal2030.pt/plano-anual-de-avisos/".freeze
      FUNDING_SOURCE = "Portugal 2030".freeze
      NATIONWIDE_REGION = /\A\s*\z|nacional|todo o territ|portugal|extra-regio/i

      THEME_PATTERNS = {
        "climate" => /climat|ambient|energia|floresta|biodivers|resíduo|economia circular|transição energética/i,
        "community_development" => /territorial|comunidade|urbana|munic|cidade|coesão|regeneração/i,
        "digital_public_services" => /digital|tecnolog|inovação|inteligente/i,
        "environment" => /ambient|biodivers|floresta|resíduo|água|mar|sustent/i,
        "inclusion" => /inclus|social|demograf|qualifica|emprego|migra|pobreza/i,
        "mobility" => /mobilidade|ferrovi|transporte/i,
        "public_space" => /urbana|territorial|regeneração|reabilitação/i
      }.freeze

      def initialize(http_client:, workbook_reader: XlsxReader.new, workbook_url: nil, plan_url: PLAN_URL)
        @http_client = http_client
        @workbook_reader = workbook_reader
        @workbook_url = workbook_url
        @plan_url = plan_url
      end

      def fetch
        rows = @workbook_reader.rows(@http_client.get(workbook_url, headers: {"Accept" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}))
        header_index = rows.index { |row| row.values.map(&:to_s).include?("ID") }
        return [] unless header_index

        headers = rows.delete_at(header_index)
        rows.filter_map { |row| normalize(headers, row) }
      rescue StandardError
        []
      end

      private

      def workbook_url
        return @workbook_url if @workbook_url

        page = @http_client.get(@plan_url, headers: {"Accept" => "text/html"})
        href = page.match(/href=["']([^"']+\.xlsx(?:\?[^"']*)?)["']/i)&.captures&.first
        href ? URI.join(@plan_url, href).to_s : WORKBOOK_URL
      rescue StandardError
        WORKBOOK_URL
      end

      def normalize(headers, row)
        data = headers.each_with_object({}) { |(column, name), result| result[name.to_s.strip] = row[column].to_s.strip }
        id = data["ID"]
        title = data["Designacao do Aviso"]
        return if id.to_s.empty? || title.to_s.empty? || !lisbon_scope?(data)

        text = data.values.join(" ")
        Opportunity.from_hash(
          "id" => "pt2030-#{id.downcase}",
          "title" => title,
          "programme" => programme(data["Programa"]),
          "opening_date" => excel_date(data["Data Inicio Prevista"]),
          "deadline" => excel_date(data["Data Fim Prevista"]),
          "funding_amount" => euro_amount(data["Dotação Fundo"]),
          "funding_source" => FUNDING_SOURCE,
          "official_link" => "#{@plan_url}#aviso-#{id}",
          "eligible_applicants" => eligible_applicants(data["Tipo Ent. Beneficiária"]),
          "partnership_requirements" => data["Modalidade Apresentação Candidatura"].to_s.include?("Parceria") ? "A modalidade do aviso prevê parceria; confirmar os requisitos no aviso oficial." : nil,
          "other_requirements" => [data["Fundo"], data["NUTS II"]].reject(&:empty?).join(" · "),
          "summary" => summary(data),
          "themes" => themes_for(text)
        )
      end

      def programme(value)
        value.to_s.split("|").map(&:strip).reject(&:empty?).join(" / ")
      end

      def lisbon_scope?(data)
        data["Programa"].to_s.match?(/(?:\A|\|\s*)LISBOA2030(?:\s*\||\z)/i) ||
          data["NUTS II"].to_s.match?(NATIONWIDE_REGION) ||
          data["NUTS II"].to_s.match?(/(?:\A|\|\s*)AML(?:\s*\||\z)/i)
      end

      def eligible_applicants(value)
        applicants = []
        applicants << "Entidades públicas" if value.to_s.match?(/Pública/i)
        applicants << "Entidades privadas" if value.to_s.match?(/Privada/i)
        applicants
      end

      def summary(data)
        details = [data["Objetivo Especifico"], data["Fundo"], data["NUTS II"]].reject(&:empty?)
        "Aviso Portugal 2030 para #{details.join("; ")}. Consultar o plano oficial para confirmar condições, documentação e candidatura."
      end

      def themes_for(text)
        THEME_PATTERNS.filter_map { |theme, pattern| theme if text.match?(pattern) }
      end

      def excel_date(value)
        number = Float(value, exception: false)
        return unless number

        (Date.new(1899, 12, 30) + number.to_i).iso8601
      end

      def euro_amount(value)
        number = Float(value, exception: false)
        return if number.nil? || number.zero?

        "€#{number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end
    end
  end
end
