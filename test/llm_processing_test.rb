require "test_helper"

class LlmProcessingTest < Minitest::Test
  class FakeClient
    attr_reader :calls

    def initialize(summary: "Resumo gerado pelo modelo.")
      @summary = summary
      @calls = []
    end

    def summarize(prompt)
      @calls << prompt
      @summary
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
      assert_equal 1, client.calls.size
      assert File.file?(File.join(dir, "#{first.cache_key}.yml"))
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

  private

  def opportunity
    FundingRadar::Opportunity.from_hash(
      "id" => "eu-1",
      "title" => "Climate call",
      "programme" => "LIFE",
      "funding_source" => "EU Funding & Tenders Portal",
      "official_link" => "https://example.test/eu-1",
      "summary" => "Resumo de origem.",
      "eligible_applicants" => ["Municípios"],
      "other_requirements" => "Confirmar no aviso.",
      "themes" => ["climate"]
    )
  end

  def build_processor(dir, enabled:, env: {"FUNDING_RADAR_LLM" => "enabled"})
    config_path = File.join(dir, "config.yml")
    File.write(config_path, {
      "profiles" => {"default" => {"instruction" => "Resume.", "max_characters" => 420}},
      "sources" => {"eu_funding_tenders" => {"enabled" => enabled, "profile" => "default", "prompt_version" => "v1"}}
    }.to_yaml)
    client = FakeClient.new
    configuration = FundingRadar::LlmProcessing::Configuration.new(path: config_path, env: env)
    processor = FundingRadar::LlmProcessing::Processor.new(
      configuration: configuration,
      cache: FundingRadar::LlmProcessing::Cache.new(directory: dir),
      client: client
    )
    [processor, client]
  end
end
