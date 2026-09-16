require "jekyll"
require "test_helper"

class AiPageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_normal_build_publishes_html_page_and_raw_skill
    Dir.mktmpdir do |destination|
      config = Jekyll.configuration(
        "source" => ROOT,
        "destination" => destination,
        "quiet" => true,
        "disable_disk_cache" => true
      )
      Jekyll::Commands::Build.process(config)

      html_path = File.join(destination, "ai", "index.html")
      raw_path = File.join(destination, "ai", "SKILL.md")
      assert File.file?(html_path)
      assert File.file?(raw_path)

      html = File.read(html_path)
      raw = File.read(raw_path)
      assert_includes html, "<title>AI Integration — Radar de Financiamento"
      assert_includes html, '<meta name="description" content="Instruções para assistentes de IA'
      assert_includes html, "Retrieval workflow"
      assert_includes html, "Interpret the JSON conservatively"
      assert_includes html, "A sua pergunta"
      assert_includes html, "https://radar-de-financiamento.decidimosarroios.pt/ai/SKILL.md"
      assert_includes html, "https://radar-de-financiamento.decidimosarroios.pt/api/v1/meta.json"
      assert_includes html, "https://radar-de-financiamento.decidimosarroios.pt/api/v1/catalog.json"
      assert_includes html, "https://radar-de-financiamento.decidimosarroios.pt/api/v1/schema.json"
      assert_includes html, "/api/v1/opportunities/{id}.json"
      assert_includes raw, "## Retrieval workflow"
      assert_equal File.read(File.join(ROOT, "ai", "SKILL.md")), raw

      refute_includes File.read(File.join(ROOT, "ai.md")), "Retrieval workflow"
      assert_includes File.read(File.join(ROOT, "llms.txt")), "AI usage instructions: https://radar-de-financiamento.decidimosarroios.pt/ai/"
    end
  end
end
