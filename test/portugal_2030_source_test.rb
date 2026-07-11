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
end
