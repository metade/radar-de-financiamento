---
layout: default
title: Arquivo
permalink: /arquivo/
---

{% assign reports = site.reports | sort: "generated_on" | reverse %}
{% assign reports = reports | where_exp: "report", "report.name != 'latest.md'" %}

<section class="bg-soft-sky">
  <div class="mx-auto max-w-6xl px-5 py-10">
    <h1 class="text-4xl font-bold text-ink">Arquivo de relatórios</h1>
    <p class="mt-4 max-w-3xl text-lg leading-8 text-slate-700">Consulte relatórios semanais anteriores e veja que oportunidades estavam identificadas em cada momento.</p>
  </div>
</section>

<section class="mx-auto max-w-6xl px-5 py-8">
  {% if reports.size > 0 %}
    <div class="space-y-4">
      {% for report in reports %}
        <article class="border border-line bg-white p-5">
          <p class="text-sm font-semibold text-civic-blue">{{ report.week_id }} · Gerado em {{ report.generated_on | date: "%d/%m/%Y" }}</p>
          <h2 class="mt-1 text-2xl font-bold text-ink">
            <a class="hover:underline" href="{{ report.url | relative_url }}">{{ report.title }}</a>
          </h2>
          <p class="mt-2 text-slate-700">{{ report.opportunities | size }} oportunidades analisadas.</p>
          <p class="mt-3"><a class="text-sm font-semibold text-civic-blue underline hover:text-ink" href="{{ '/relatorios/' | append: report.name | replace: '.md', '' | append: '.csv' | relative_url }}">Descarregar CSV</a></p>
        </article>
      {% endfor %}
    </div>
  {% else %}
    <p class="text-lg text-slate-700">Ainda não existem relatórios arquivados.</p>
  {% endif %}
</section>
