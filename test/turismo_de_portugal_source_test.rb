require "test_helper"

class TurismoDePortugalSourceTest < Minitest::Test
  FakeHttpClient = Struct.new(:pages) do
    def get(url, headers: {})
      pages.fetch(url)
    end
  end

  def test_fetches_listing_entries_and_enriches_detail_pages
    listing_url = "https://business.example/calls"
    first = "https://business.example/aviso-energia.aspx"
    second = "https://business.example/call-interior.aspx"
    listing = <<~HTML
      <a href="#{first}">Aviso Descarbonização e Eficiência Energética - candidaturas a decorrer</a>
      <a href="#{second}">Call Fundo de Investimento para o Turismo no Interior - candidaturas a decorrer</a>
      <a href="/candidaturas-avisos-concurso-encerrados.aspx">Aviso encerrado</a>
    HTML
    pages = {
      listing_url => listing,
      first => "<h1>Aviso Descarbonização e Eficiência Energética</h1><p>Período de candidaturas até 27/02/2026.</p><p>Dotação: 12.500.000 €</p><p>Podem candidatar-se empresas e entidades públicas.</p>",
      second => "<h1>Call Fundo de Investimento para o Turismo no Interior</h1><p>Prazo de candidaturas até 31/12/2026.</p><p>Financiamento de 5 000 000 euros para municípios e empresas.</p>"
    }

    source = FundingRadar::Sources::TurismoDePortugalSource.new(http_client: FakeHttpClient.new(pages), listing_url: listing_url)
    opportunities = source.fetch

    assert_equal ["Aviso Descarbonização e Eficiência Energética", "Call Fundo de Investimento para o Turismo no Interior"], opportunities.map(&:title)
    assert_equal "2026-02-27", opportunities.first.deadline
    assert_equal "€12,500,000", opportunities.first.funding_amount
    assert_equal ["Entidades públicas", "Entidades privadas"], opportunities.first.eligible_applicants
    assert_includes opportunities.first.themes, "climate"
  end

  def test_keeps_listing_record_when_detail_page_is_unavailable
    listing_url = "https://business.example/calls"
    link = "https://business.example/missing.aspx"
    client = FakeHttpClient.new({listing_url => %(<a href="#{link}">Aviso Turismo aberto</a>), link => nil})
    opportunity = FundingRadar::Sources::TurismoDePortugalSource.new(http_client: client, listing_url: listing_url).fetch.first

    assert_equal "Aviso Turismo aberto", opportunity.title
    assert_nil opportunity.deadline
  end

  def test_skips_notice_restricted_to_private_companies
    listing_url = "https://business.example/calls"
    link = "https://business.example/private-only.aspx"
    pages = {
      listing_url => %(<a href="#{link}">Call Turismo no Interior - candidaturas a decorrer</a>),
      link => "<p>Destinatários: empresas e PME proprietárias de imóveis. O projeto deve localizar-se em território de baixa densidade.</p>"
    }

    opportunities = FundingRadar::Sources::TurismoDePortugalSource.new(http_client: FakeHttpClient.new(pages), listing_url: listing_url).fetch

    assert_empty opportunities
  end
end
