---
layout: default
title: Usar o Radar com assistentes de IA
permalink: /ia/
---

# Usar o Radar com assistentes de IA

O Funding Radar disponibiliza uma API pública composta apenas por ficheiros JSON estáticos. Não há pesquisa dinâmica nem chamadas de IA quando estes ficheiros são consultados.

## Fluxo recomendado

1. Consulte [`/api/v1/meta.json`]({{ '/api/v1/meta.json' | relative_url }}) para verificar a data de geração e a frescura do catálogo.
2. Consulte [`/api/v1/catalog.json`]({{ '/api/v1/catalog.json' | relative_url }}).
3. Interprete o projeto do utilizador e crie conceitos, sinónimos e temas de financiamento adjacentes.
4. Pesquise e filtre o catálogo localmente.
5. Escolha um pequeno número de oportunidades plausíveis.
6. Consulte os detalhes em `/api/v1/opportunities/{id}.json` para esses candidatos.
7. Confirme elegibilidade, geografia, prazo, condições de financiamento e exclusões.
8. Explique por que razão uma oportunidade pode ou não se adequar ao projeto.
9. Inclua sempre uma ligação para a fonte oficial da oportunidade.
10. Explique que a análise gerada pelo Funding Radar é orientação e que a documentação oficial do programa é a autoridade.

Os campos em `facts` representam informação extraída ou normalizada a partir do aviso. Os campos em `analysis` são interpretação editorial/determinística ou gerada por LLM e não substituem o aviso oficial. A proveniência e as ligações autoritativas encontram-se em `provenance` e `links`.

`facts.applicant_eligibility_status` distingue `known` de `unknown`. Uma lista de candidatos ausente ou com estado `unknown` significa que o Funding Radar não estabeleceu a elegibilidade; nunca significa que todas as organizações podem candidatar-se. `facts.geography`, quando presente, é uma indicação estruturada baseada em dados explícitos da fonte. Confirme sempre elegibilidade e âmbito territorial no aviso oficial.

O enriquecimento LLM é feito durante a geração agendada e tem versão de prompt. Caches de versões antigas são ignorados automaticamente na próxima execução; para uma re-enriquecimento controlado, use `REPORT_PROCESSING=source_config FUNDING_RADAR_LLM=enabled` e limite a amostra com `--tenders-per-source N`.
