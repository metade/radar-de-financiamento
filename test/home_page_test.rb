require "jekyll"
require "test_helper"

class HomePageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_homepage_links_to_ai_page_next_to_csv_download
    Dir.mktmpdir do |destination|
      config = Jekyll.configuration(
        "source" => ROOT,
        "destination" => destination,
        "quiet" => true,
        "disable_disk_cache" => true
      )
      Jekyll::Commands::Build.process(config)

      html = File.read(File.join(destination, "index.html"))
      assert_includes html, "Radar de Financiamento para autarquias"
      assert_includes html, ">Descarregar oportunidades em CSV</a>"
      assert_includes html, 'href="/ai/">Experimentar com IA</a>'
    end
  end
end
