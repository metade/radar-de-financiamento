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
