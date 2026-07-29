require "test_helper"

class ImtMobilityFundSourceTest < Minitest::Test
  FakeHttpClient = Struct.new(:pages) do
    def get(url, headers: {})
      pages.fetch(url)
    end
  end

  def test_discovers_year_pages_and_normalizes_open_notices
    index_url = "https://imt.example/notices/"
    year_url = "https://imt.example/notices/2026/"
    notice_url = "https://imt.example/concurso/aviso-1/"
    pdf_url = "https://imt.example/uploads/aviso-1.pdf"
    pages = {
      index_url => %(<h2><a href="#{year_url}">2026</a></h2>),
      year_url => <<~HTML,
        <div class="notice">
          <h3><a href="#{notice_url}">Aviso n.º 1/2026 – Apoio à Mobilidade Sustentável</a></h3>
          <a href="#{pdf_url}">Aviso n.º 1/2026</a>
          <a href="https://imt.example/forms/formulario.html">Formulário de Candidatura</a>
        </div>
      HTML
      notice_url => <<~HTML,
        <h1>Aviso n.º 1/2026 – Apoio à Mobilidade Sustentável</h1>
        <p>Prazo de submissão de candidaturas até 31/12/2026.</p>
        <p>Dotação financeira: 2.500.000 €.</p>
        <p>Beneficiários: municípios e autoridades de transporte.</p>
        <a href="https://www.imt-ip.pt/wp-content/uploads/2025/03/Organogramas-IMT.pdf">Organogramas IMT</a>
      HTML
    }

    opportunity = FundingRadar::Sources::ImtMobilityFundSource.new(
      http_client: FakeHttpClient.new(pages), index_url: index_url
    ).fetch.first

    assert_equal "Aviso n.º 1/2026 – Apoio à Mobilidade Sustentável", opportunity.title
    assert_equal "2026-12-31", opportunity.deadline
    assert_equal "€2,500,000", opportunity.funding_amount
    assert_equal ["Entidades públicas"], opportunity.eligible_applicants
    assert_equal pdf_url, opportunity.document_link
    assert_includes opportunity.themes, "mobility"
  end

  def test_skips_closed_and_past_notices_but_keeps_valid_notice_when_detail_is_missing
    index_url = "https://imt.example/notices/"
    year_url = "https://imt.example/notices/2026/"
    open_url = "https://imt.example/concurso/open/"
    closed_url = "https://imt.example/concurso/closed/"
    past_url = "https://imt.example/concurso/past/"
    pages = {
      index_url => %(<a href="#{year_url}">2026</a>),
      year_url => <<~HTML,
        <h3><a href="#{open_url}">Aviso n.º 1/2026 – Apoio aberto</a></h3>
        <h3><a href="#{closed_url}">Aviso n.º 2/2026 – Apoio encerrado</a></h3>
        <h3><a href="#{past_url}">Aviso n.º 3/2026 – Apoio terminado</a></h3>
      HTML
      open_url => nil,
      closed_url => "<h1>Aviso n.º 2/2026</h1><p>Candidaturas encerradas.</p>",
      past_url => "<h1>Aviso n.º 3/2026</h1><p>Prazo de candidaturas até 01/01/2026.</p>"
    }

    opportunities = FundingRadar::Sources::ImtMobilityFundSource.new(
      http_client: FakeHttpClient.new(pages), index_url: index_url
    ).fetch

    assert_equal ["Aviso n.º 1/2026 – Apoio aberto"], opportunities.map(&:title)
  end

  def test_falls_back_to_conventional_year_url_when_index_has_no_year_links
    index_url = "https://imt.example/notices/"
    year_url = "https://imt.example/notices/avisos-de-candidatura-2026/"
    pages = {
      index_url => "<h2>2026</h2>",
      year_url => "<h3><a href=\"https://imt.example/concurso/open/\">Aviso n.º 1/2026 – Apoio</a></h3>",
      "https://imt.example/concurso/open/" => "<p>Prazo de candidaturas até 31/12/2026.</p>"
    }

    opportunities = FundingRadar::Sources::ImtMobilityFundSource.new(
      http_client: FakeHttpClient.new(pages), index_url: index_url
    ).fetch

    assert_equal ["Aviso n.º 1/2026 – Apoio"], opportunities.map(&:title)
  end

  def test_only_fetches_current_and_previous_year
    index_url = "https://imt.example/notices/"
    current_url = "https://imt.example/notices/2026/"
    previous_url = "https://imt.example/notices/2025/"
    old_url = "https://imt.example/notices/2024/"
    pages = {
      index_url => <<~HTML,
        <a href="#{current_url}">2026</a>
        <a href="#{previous_url}">2025</a>
        <a href="#{old_url}">2024</a>
      HTML
      current_url => "<h3><a href=\"https://imt.example/concurso/current/\">Aviso atual</a></h3>",
      previous_url => "<h3><a href=\"https://imt.example/concurso/previous/\">Aviso anterior</a></h3>",
      "https://imt.example/concurso/current/" => "<p>Prazo até 31/12/2026.</p>",
      "https://imt.example/concurso/previous/" => "<p>Prazo até 31/12/2026.</p>"
    }

    opportunities = FundingRadar::Sources::ImtMobilityFundSource.new(
      http_client: FakeHttpClient.new(pages), index_url: index_url
    ).fetch

    assert_equal ["Aviso atual", "Aviso anterior"], opportunities.map(&:title)
  end
end
