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
        "layout" => "default",
        "title" => "AI Integration — Radar de Financiamento",
        "description" => "Instruções para assistentes de IA consultarem a API pública de oportunidades de financiamento do Radar de Financiamento."
      }
      page.content = page_content(site, skill_path)
      site.pages << page
    end

    private

    def page_content(site, skill_path)
      base_url = [site.config["url"], site.config["baseurl"]].compact.join
      base_url = "https://radar-de-financiamento.decidimosarroios.pt" if base_url.empty?
      skill_url = "#{base_url}/ai/SKILL.md"
      meta_url = "#{base_url}/api/v1/meta.json"
      catalog_url = "#{base_url}/api/v1/catalog.json"
      schema_url = "#{base_url}/api/v1/schema.json"
      skill_html = Kramdown::Document.new(skill_markdown(skill_path), input: "GFM").to_html

      <<~HTML
        <section class="bg-soft-sky">
          <div class="mx-auto max-w-6xl px-5 py-10">
            <p class="text-sm font-semibold uppercase tracking-wide text-civic-blue">Integração pública</p>
            <h1 class="mt-2 max-w-4xl text-3xl font-bold text-ink sm:text-5xl">Radar de Financiamento — instruções para IA</h1>
            <p class="mt-4 max-w-3xl text-lg leading-8 text-slate-700">O Radar de Financiamento publica dados estáticos sobre oportunidades de financiamento público. Estas instruções explicam como um assistente de IA deve usar o conjunto de dados para encontrar oportunidades relevantes.</p>
            <p class="mt-4 max-w-3xl text-slate-700">O Radar não opera um chatbot nem faz inferência LLM por consulta. Pode usar o seu próprio assistente; a conversa e o raciocínio são feitos por esse assistente, enquanto o Radar disponibiliza uma API pública gerada periodicamente. Confirme sempre elegibilidade e condições na fonte oficial.</p>
            <div class="mt-6 flex flex-wrap gap-x-6 gap-y-3 text-sm font-semibold">
              <a class="text-civic-blue underline hover:text-ink" href="#{skill_url}">Ver SKILL.md original</a>
              <a class="text-civic-blue underline hover:text-ink" href="#{meta_url}">API: metadados</a>
              <a class="text-civic-blue underline hover:text-ink" href="#{catalog_url}">API: catálogo</a>
              <a class="text-civic-blue underline hover:text-ink" href="#{schema_url}">API: schema</a>
            </div>
          </div>
        </section>

        <div class="mx-auto max-w-6xl px-5 py-10">
          <section class="mb-10 border border-line bg-white p-6" aria-labelledby="como-funciona">
            <h2 id="como-funciona" class="text-2xl font-bold text-ink">Como funciona</h2>
            <p class="mt-4 font-mono text-sm leading-7 text-slate-700">A sua pergunta → o seu assistente de IA → API pública estática do Radar de Financiamento → fontes oficiais de financiamento</p>
            <p class="mt-4 text-slate-700">Os detalhes individuais estão disponíveis em <code>/api/v1/opportunities/{id}.json</code> ou através de <code>detail_url</code> nos registos do catálogo.</p>
          </section>

          <section class="mb-10 border-l-4 border-civic-gold bg-soft-amber p-6" aria-labelledby="exemplo">
            <h2 id="exemplo" class="text-xl font-bold text-ink">Exemplo de utilização</h2>
            <p class="mt-3 text-slate-700">“Somos uma Junta de Freguesia em Lisboa e queremos plantar árvores, criar mais sombra e melhorar os parques infantis. Que oportunidades de financiamento devemos investigar?”</p>
          </section>

          <article class="max-w-4xl text-slate-700">
            #{skill_html}
          </article>
        </div>
      HTML
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
