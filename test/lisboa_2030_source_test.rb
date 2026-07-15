require "test_helper"

class Lisboa2030SourceTest < Minitest::Test
  class FakeLisboaHttpClient
    attr_reader :forms

    def initialize(payload)
      @payload = payload
      @forms = []
    end

    def post_form(_url, form:, headers: {})
      @forms << form
      @payload
    end
  end

  def test_extracts_open_lisboa_notice_from_official_json_catalogue
    payload = {
      "avisos" => [{
        "aviso" => {"codigoAviso" => "LISBOA2030-2026-4", "designacaoPT" => "Redes e capacitação institucional RIS3"},
        "calendario" => {"dataInicio" => "2026-06-01T00:00:00", "dataFimAtual" => "2026-07-31T18:00:00"},
        "estrutura" => [{"programaOperacionalId" => 105, "dotacao" => 400000, "programaOperacionalDesignacao" => "Programa Regional de Lisboa 2021-2027"}],
        "documentos" => [{"tipoDocumentoDesignacao" => "Aviso", "container" => "siag-prod-container", "path" => "avisos/2026/6/test.pdf"}]
      }],
      "status" => 200
    }
    client = FakeLisboaHttpClient.new(JSON.generate(payload))
    source = FundingRadar::Sources::Lisboa2030Source.new(http_client: client, query_url: "https://example.test/wp-json/avisos/query")

    opportunity = source.fetch.first

    assert_equal "lisboa2030-2026-4", opportunity.id
    assert_equal "2026-06-01", opportunity.opening_date
    assert_equal "2026-07-31", opportunity.deadline
    assert_equal "€400,000", opportunity.funding_amount
    assert_equal "lisboa_2030", opportunity.source_key
    assert_equal "https://lisboa.portugal2030.pt/avisos/#aviso-lisboa2030-2026-4", opportunity.official_link
    assert_equal "https://example.test/wp-json/avisos/download?container=siag-prod-container&path=avisos%2F2026%2F6%2Ftest.pdf", opportunity.document_link
    assert_equal 1, client.forms.size
    assert_equal 105, client.forms.first[:programaId]
    assert_equal 7, client.forms.first[:estadoAvisoId]
  end

  def test_ignores_non_lisboa_records_returned_by_the_shared_catalogue
    payload = {"avisos" => [{"aviso" => {"codigoAviso" => "MPr-2026-7", "designacaoPT" => "Outro aviso"}}], "status" => 200}
    source = FundingRadar::Sources::Lisboa2030Source.new(http_client: FakeLisboaHttpClient.new(JSON.generate(payload)))

    assert_empty source.fetch
  end
end
