require "fileutils"
require "kramdown"

module FundingRadar
  class AiPageGenerator < Jekyll::Generator
    safe true
    priority :low

    def generate(site)
      skill_path = File.join(site.source, "ai", "SKILL.md")
      return unless File.file?(skill_path)

      page = Jekyll::PageWithoutAFile.new(site, site.source, "ai", "index.html")
      page.data = {
        "layout" => "ai",
        "title" => "AI Integration — Radar de Financiamento",
        "description" => "Instruções para assistentes de IA consultarem a API pública de oportunidades de financiamento do Radar de Financiamento."
      }
      page.content = render_skill(skill_path)
      site.pages << page
    end

    private

    def render_skill(path)
      Kramdown::Document.new(skill_markdown(path), input: "GFM").to_html
    end

    def skill_markdown(path)
      File.read(path, encoding: "UTF-8").sub(/\A---\s*\n.*?\n---\s*\n/m, "")
    end
  end
end

Jekyll::Hooks.register :site, :post_write do |site|
  source_root = File.join(site.source, "ai")
  next unless Dir.exist?(source_root)

  Dir[File.join(source_root, "**", "*.md")].each do |source_path|
    relative_path = source_path.delete_prefix("#{source_root}/")
    destination_path = File.join(site.dest, "ai", relative_path)
    FileUtils.mkdir_p(File.dirname(destination_path))
    FileUtils.cp(source_path, destination_path)
  end
end
