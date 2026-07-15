require "test_helper"

class Portugal2030SourceTest < Minitest::Test
  class FakeWorkbookReader
    def initialize(rows)
      @payload = rows
    end

    def rows(_contents)
      @payload
    end
  end
  PortugalFakeHttpClient = Struct.new(:body) do
    def get(_url, headers: {})
      body
    end
  end

  class PortugalPlanFakeHttpClient
    attr_reader :requested_urls

    def initialize(plan:, workbook: "xlsx")
      @plan = plan
      @workbook = workbook
      @requested_urls = []
    end

    def get(url, headers: {})
      @requested_urls << url
      url.end_with?("/plan") ? @plan : @workbook
    end
  end

  def test_fetches_and_normalizes_open_data_rows
    headers = {"A" => "ID", "B" => "Tipo Ent. Beneficiária", "C" => "Designacao do Aviso", "D" => "Programa", "E" => "Objetivo Especifico", "F" => "Fundo", "G" => "Dotação Fundo", "H" => "Data Inicio Prevista", "I" => "Data Fim Prevista", "J" => "NUTS II", "K" => "Modalidade Apresentação Candidatura"}
    row = {"A" => "7900", "B" => "Pública", "C" => "Gestão de Resíduos Urbanos", "D" => "SUSTENTAVEL2030", "E" => "RSO2.6 - Economia circular", "F" => "FEDER", "G" => "990000", "H" => "46272", "I" => "46325", "J" => "AML", "K" => "Individual"}
    non_lisbon_row = row.merge("A" => "7901", "D" => "NORTE2030", "J" => "Norte")
    nationwide_row = row.merge("A" => "7902", "D" => "COMPETE2030", "J" => "")
    source = FundingRadar::Sources::Portugal2030Source.new(
      http_client: PortugalFakeHttpClient.new("xlsx"),
      workbook_reader: FakeWorkbookReader.new([headers, row, non_lisbon_row, nationwide_row]),
      plan_url: "https://example.test/plan"
    )

    opportunities = source.fetch
    opportunity = opportunities.first

    assert_equal "pt2030-7900", opportunity.id
    assert_equal "Gestão de Resíduos Urbanos", opportunity.title
    assert_equal "SUSTENTAVEL2030", opportunity.programme
    assert_equal "2026-09-07", opportunity.opening_date
    assert_equal "2026-10-30", opportunity.deadline
    assert_equal "€990,000", opportunity.funding_amount
    assert_equal ["Entidades públicas"], opportunity.eligible_applicants
    assert_includes opportunity.themes, "environment"
    assert_equal "https://example.test/plan#aviso-7900", opportunity.official_link
    assert_equal ["pt2030-7900", "pt2030-7902"], opportunities.map(&:id)
  end

  def test_prefers_the_direct_aviso_page_link_from_the_plan
    headers = {"A" => "ID", "B" => "Tipo Ent. Beneficiária", "C" => "Designacao do Aviso", "D" => "Programa", "E" => "Objetivo Especifico", "F" => "Fundo", "G" => "Dotação Fundo", "H" => "Data Inicio Prevista", "I" => "Data Fim Prevista", "J" => "NUTS II", "K" => "Modalidade Apresentação Candidatura"}
    row = {"A" => "7906", "B" => "Pública", "C" => "Inquéritos de mobilidade nas Áreas Metropolitana de Lisboa e do Porto", "D" => "SUSTENTAVEL2030", "E" => "RSO2.8 - Mobilidade urbana sustentável", "F" => "FC", "G" => "1000000", "H" => "46366", "I" => "46544", "J" => "Norte | AML", "K" => "Individual"}
    direct_link = "https://example.test/aviso-2024/inqueritos-de-mobilidade-nas-areas-metropolitana-de-lisboa-e-do-porto/"
    client = PortugalPlanFakeHttpClient.new(plan: %(<h3><a class="card-link" href="#{direct_link}"></a><a class="card-link" href="#{direct_link}"><span>Inqueritos de mobilidade nas Areas Metropolitana de Lisboa e do Porto</span> — previsão</a></h3>))
    source = FundingRadar::Sources::Portugal2030Source.new(
      http_client: client,
      workbook_reader: FakeWorkbookReader.new([headers, row]),
      plan_url: "https://example.test/plan"
    )

    assert_equal direct_link, source.fetch.first.official_link
  end
end
