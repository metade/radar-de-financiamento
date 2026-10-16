require "test_helper"

class EdpSolidariaSourceTest < Minitest::Test
  Source = FundingRadar::Sources::EdpSolidariaSource
  RULES_URL = "https://www.fundacaoedp.pt/pt/conteudo/regulamento".freeze
  FakeHttpClient = Struct.new(:pages) do
    def get(url, headers: {})
      pages.fetch(url)
    end
  end

  def programme(status: "Candidaturas abertas.", edition: "2025 - 2026")
    <<~HTML
      <nav>Resultados publicados</nav>
      <article><section class="content"><div>
        <h2>Edição #{edition}</h2>
        <p>#{status}</p>
        <p>Apoio a projetos sociais de transição energética justa para pessoas em situação de vulnerabilidade.
        Temas: inclusão e eficiência energética, mobilidade sustentável, património natural e economia circular.</p>
      </div></section>
      <section><h2>O programa</h2><p>Desde 2004, investimento de 20 milhões de euros.</p></section>
      <section><a href="/pt/conteudo/regulamento"><h3>Regulamento</h3></a></section>
      <section><h2>Projetos já apoiados</h2><p>Vencedores foram anunciados em 2024.</p></section></article>
    HTML
  end

  def rules
    <<~HTML
      <article><h1>Regulamento</h1><a href="/regulamento-2025.pdf">Regulamento 2025</a>
      <ul>
        <li>Candidaturas simplificadas (fase 1): a decorrer entre os dias 1 de abril e 31 de maio de 2025, para apresentação de notas de conceito;</li>
        <li>Candidaturas detalhadas (fase 2): a decorrer entre os dias 1 de outubro e 30 de novembro de 2025, para candidaturas pré-selecionadas.</li>
      </ul>
      <p>Podem candidatar-se entidades nacionais legalmente constituídas nas seguintes categorias:</p>
      <ul><li>entidades sem fins lucrativos (entidades da economia social e organismos públicos: escolas, universidades ou politécnicos);</li>
      <li>ou com fins lucrativos.</li></ul>
      <p>Os organismos públicos que não sejam escolas, universidades ou politécnicos não podem apresentar candidaturas, a nível individual, ou como líderes de parceria. No entanto, podem ser parceiros em projetos liderados por uma entidade elegível.</p>
      <p>As entidades devem estar legalmente constituídas há pelo menos um ano.</p>
      <p>Só são aceites projetos a desenvolver em território nacional.</p>
      <p>O valor global do apoio da Fundação EDP por cada projeto não poderá ser inferior a 15.000 € (quinze mil euros), nem superior a 100.000 € (cem mil euros).</p>
      </article>
    HTML
  end

  def fetch(page: programme, rules_html: rules, today: Date.new(2025, 4, 15))
    Source.new(http_client: FakeHttpClient.new({Source::INDEX_URL => page, RULES_URL => rules_html}), today: today).fetch
  end

  def test_normalizes_first_phase_and_preserves_partner_only_public_eligibility
    opportunity = fetch.first

    assert_equal "edp-solidaria-2025-2026", opportunity.id
    assert_equal "EDP Energia Solidária — Edição 2025–2026", opportunity.title
    assert_equal "Fundação EDP", opportunity.funding_source
    assert_equal "edp_solidaria", opportunity.source_key
    assert_equal "2025-04-01", opportunity.opening_date
    assert_equal "2025-05-31", opportunity.deadline
    assert_equal "15.000 € a 100.000 € por projeto", opportunity.funding_amount
    assert_equal Source::INDEX_URL, opportunity.official_link
    assert_equal RULES_URL, opportunity.document_link
    assert_equal 2, opportunity.eligible_applicants.size
    assert_includes opportunity.eligible_applicants.first, "escolas, universidades ou politécnicos"
    assert_includes opportunity.partnership_requirements, "não podem apresentar candidaturas"
    assert_includes opportunity.partnership_requirements, "podem ser parceiros"
    assert_includes opportunity.other_requirements, "pelo menos um ano"
    assert_equal({"scope" => "national", "areas" => ["Portugal"]}, opportunity.geography)
    assert_equal %w[climate inclusion environment mobility], opportunity.themes
    refute_includes opportunity.summary, "20 milhões"
    refute_includes opportunity.summary, "Vencedores"
  end

  def test_completed_edition_is_skipped_even_if_rules_are_unavailable
    assert_empty fetch(page: programme(status: "Os vencedores foram conhecidos no dia 19 de maio de 2026."), rules_html: nil)
    assert_empty fetch(page: programme(status: "Candidaturas encerradas."))
    assert_empty fetch(page: programme(status: "Resultados publicados."))
  end

  def test_phase_two_does_not_extend_deadline_for_new_applicants
    assert_empty fetch(today: Date.new(2025, 10, 15))
    assert_equal 1, fetch(today: Date.new(2025, 5, 31)).size
  end

  def test_upcoming_call_is_kept_and_numeric_dates_are_supported
    payload = rules.sub("1 de abril e 31 de maio de 2025", "01/04/2025 e 31/05/2025")
    opportunity = fetch(rules_html: payload, today: Date.new(2025, 3, 1)).first
    assert_equal "2025-04-01", opportunity.opening_date
    assert_equal "2025-05-31", opportunity.deadline
  end

  def test_explicit_open_call_survives_missing_rules_without_inventing_facts
    opportunity = fetch(rules_html: nil).first
    assert_nil opportunity.deadline
    assert_nil opportunity.opening_date
    assert_empty opportunity.funding_amount
    assert_empty opportunity.eligible_applicants
    assert_equal "unknown", opportunity.geography["scope"]
  end

  def test_new_edition_does_not_reuse_old_rules
    opportunity = fetch(page: programme(edition: "2027 - 2028"), today: Date.new(2027, 4, 1)).first
    assert_equal "edp-solidaria-2027-2028", opportunity.id
    assert_nil opportunity.deadline
    assert_empty opportunity.funding_amount
    assert_empty opportunity.eligible_applicants
  end

  def test_generic_programme_without_application_evidence_is_not_a_call
    assert_empty fetch(page: programme(status: "Programa de apoio social."), rules_html: "<h1>Regulamento</h1>")
    assert_empty fetch(page: "<article><h2>O programa</h2><p>Candidaturas abertas em 2023.</p></article>")
  end

  def test_invalid_dates_remain_unknown
    opportunity = fetch(rules_html: rules.sub("31 de maio", "32 de maio")).first
    assert_nil opportunity.deadline

    opportunity = fetch(rules_html: rules.sub("31 de maio de 2025", "31 de maio")).first
    assert_nil opportunity.opening_date
    assert_nil opportunity.deadline
  end

  def test_fetch_failure_is_nonfatal
    assert_empty Source.new(http_client: FakeHttpClient.new({})).fetch
  end
end
