require "test_helper"

class LlmProcessingTest < Minitest::Test
  class FakeClient
    attr_reader :calls

    def initialize(attributes: nil)
      @attributes = attributes || {
        "summary" => "Resumo gerado pelo modelo.",
        "themes" => ["climate"],
        "eligibility" => {"status" => "unclear", "criteria" => [], "confidence" => "low"},
        "partnership" => {"status" => "not_stated", "details" => "", "confidence" => "low"}
      }
      @calls = []
    end

    def analyze(prompt)
      @calls << prompt
      @attributes
    end
  end

  class FakeDocumentFetcher
    attr_reader :urls

    def initialize(body = "PDF bytes")
      @body = body
      @urls = []
    end

    def get(url, headers: {})
      @urls << [url, headers]
      @body
    end
  end

  class FakeDocumentExtractor
    def initialize(text)
      @text = text
    end

    def extract(_body)
      @text
    end
  end

  def test_disabled_source_does_not_call_provider
    Dir.mktmpdir do |dir|
      processor, client = build_processor(dir, enabled: false)

      result = processor.process(opportunity)

      assert_equal "disabled", result.status
      assert_equal opportunity.summary, result.summary
      assert_empty client.calls
    end
  end

  def test_global_switch_overrides_enabled_source
    Dir.mktmpdir do |dir|
      processor, client = build_processor(dir, enabled: true, env: {"FUNDING_RADAR_LLM" => "disabled"})

      result = processor.process(opportunity)

      assert_equal "disabled", result.status
      assert_empty client.calls
    end
  end

  def test_generates_and_reuses_versioned_cache
    Dir.mktmpdir do |dir|
      processor, client = build_processor(dir, enabled: true)

      first = processor.process(opportunity)
      second = processor.process(opportunity)

      assert_equal "generated", first.status
      assert_equal "cached", second.status
      assert_equal first.summary, second.summary
      assert_equal ["climate"], second.themes
      assert_equal "unclear", second.analysis.fetch("eligibility").fetch("status")
      assert_equal 1, client.calls.size
      assert_equal 1, Dir[File.join(dir, "**", "#{first.cache_key}.yml")].size
    end
  end

  def test_source_content_change_invalidates_cache
    Dir.mktmpdir do |dir|
      processor, client = build_processor(dir, enabled: true)

      processor.process(opportunity)
      changed = opportunity.with(summary: "Resumo de origem atualizado.")
      result = processor.process(changed)

      assert_equal "generated", result.status
      assert_equal 2, client.calls.size
    end
  end

  def test_prompt_configuration_change_invalidates_cache
    Dir.mktmpdir do |dir|
      first_processor, first_client = build_processor(dir, enabled: true, max_characters: 420)
      first_processor.process(opportunity)

      second_processor, second_client = build_processor(dir, enabled: true, max_characters: 410)
      result = second_processor.process(opportunity)

      assert_equal "generated", result.status
      assert_equal 1, first_client.calls.size
      assert_equal 1, second_client.calls.size
      cache_files = Dir[File.join(dir, "**", "*.yml")].reject { |path| path.end_with?("config.yml") }
      assert_equal 2, cache_files.size
    end
  end

  def test_does_not_cut_model_output_at_a_character_boundary
    Dir.mktmpdir do |dir|
      client = FakeClient.new(attributes: {
        "summary" => "Uma frase completa que ultrapassa o limite configurado.",
        "themes" => ["climate"],
        "eligibility" => {"status" => "unclear", "criteria" => [], "confidence" => "low"},
        "partnership" => {"status" => "not_stated", "details" => "", "confidence" => "low"}
      })
      processor, = build_processor(dir, enabled: true, client: client, max_characters: 10)

      result = processor.process(opportunity)

      assert_equal "Uma frase completa que ultrapassa o limite configurado.", result.summary
      assert_includes client.calls.first, "summary até 10 caracteres"
    end
  end

  def test_lisboa_profile_fetches_pdf_text_and_includes_it_in_prompt
    Dir.mktmpdir do |dir|
      client = FakeClient.new
      fetcher = FakeDocumentFetcher.new
      processor, = build_processor(
        dir,
        enabled: true,
        client: client,
        source_key: "lisboa_2030",
        document_fetcher: fetcher,
        document_extractor: FakeDocumentExtractor.new("Beneficiários: municípios. Parceria opcional.")
      )

      result = processor.process(lisboa_opportunity)

      assert_equal "generated", result.status
      assert_equal [[lisboa_opportunity.document_link, {"Accept" => "application/pdf"}]], fetcher.urls
      assert_includes client.calls.first, "Beneficiários: municípios. Parceria opcional."
    end
  end

  def test_exposes_dates_returned_by_the_llm
    Dir.mktmpdir do |dir|
      client = FakeClient.new(attributes: {
        "summary" => "Resumo.",
        "opening_date" => "2026-08-05",
        "deadline" => "2026-08-28",
        "themes" => [],
        "eligibility" => {"status" => "unclear", "criteria" => [], "confidence" => "low"},
        "partnership" => {"status" => "not_stated", "details" => "", "confidence" => "low"}
      })
      processor, = build_processor(dir, enabled: true, client: client)

      result = processor.process(opportunity)

      assert_equal "2026-08-05", result.opening_date
      assert_equal "2026-08-28", result.deadline
    end
  end

  def test_structured_schema_supports_date_fields
    require "ruby_llm"
    require "ruby_llm/schema"

    assert FundingRadar::LlmProcessing::StructuredSchema.build
  end

  private

  def opportunity
    FundingRadar::Opportunity.from_hash(
      "id" => "eu-1",
      "title" => "Climate call",
      "programme" => "LIFE",
      "funding_source" => "EU Funding & Tenders Portal",
      "source_key" => "eu_funding_tenders",
      "official_link" => "https://example.test/eu-1",
      "summary" => "Resumo de origem.",
      "eligible_applicants" => ["Municípios"],
      "other_requirements" => "Confirmar no aviso.",
      "themes" => ["climate"]
    )
  end

  def build_processor(dir, enabled:, env: {"FUNDING_RADAR_LLM" => "enabled"}, client: nil, max_characters: 420, source_key: "eu_funding_tenders", document_fetcher: nil, document_extractor: nil)
    config_path = File.join(dir, "config.yml")
    File.write(config_path, {
      "profiles" => {"default" => {"instruction" => "Resume.", "max_characters" => max_characters, "include_document" => source_key == "lisboa_2030"}},
      "sources" => {source_key => {"enabled" => enabled, "profile" => "default", "prompt_version" => "v1"}}
    }.to_yaml)
    client ||= FakeClient.new
    configuration = FundingRadar::LlmProcessing::Configuration.new(path: config_path, env: env)
    processor = FundingRadar::LlmProcessing::Processor.new(
      configuration: configuration,
      cache: FundingRadar::LlmProcessing::Cache.new(directory: dir),
      client: client,
      document_fetcher: document_fetcher,
      document_extractor: document_extractor
    )
    [processor, client]
  end

  def lisboa_opportunity
    opportunity.with(
      id: "lisboa2030-2026-4",
      programme: "LISBOA2030",
      funding_source: "Portugal 2030",
      source_key: "lisboa_2030",
      document_link: "https://example.test/aviso.pdf"
    )
  end
end
