# Radar de Financiamento da UE

Static funding intelligence service for Portuguese local authorities. The site publishes a weekly digest of public funding opportunities and highlights which calls are most relevant for municipalities, parish councils, and other local public bodies.

The project uses Ruby, Jekyll, Tailwind CSS, and GitHub Actions. It does not use Rails, a database, or a backend server.

## Local Development

Install Ruby and Node dependencies:

```sh
bundle install
npm install
```

Generate the current weekly report:

```sh
bundle exec ruby bin/generate_report
```

Build CSS and the static site:

```sh
npm run build:css
bundle exec jekyll build
```

Run tests:

```sh
bundle exec rake test
```

## How Reports Are Generated

The generation pipeline is implemented in `lib/funding_radar`.

1. Source adapters load raw opportunities.
2. Opportunities are normalized into a common Ruby object.
3. Duplicate opportunities are removed deterministically.
4. The relevance scorer assigns a score, category, explanation, and suggested next step.
5. A dated ISO-week report is written to `_reports/YYYY-Www.md`, with a matching `_reports/YYYY-Www.csv` export of its opportunities.
6. Jekyll renders the homepage, individual report pages, and archive.

By default, report generation queries the official EU Funding & Tenders Portal search API, the official Portugal 2030 annual notice plan workbook, the Interreg Sudoe call pages, and the European Urban Initiative call catalogue, normalizing them into the same opportunity model. Fixture data remains available for local fallback and demos.

HTTP responses are cached in `tmp/cache/funding_radar` for six hours by default. This avoids repeating source requests during local inspection and report generation while keeping the cache out of the generated site. Configure it with `FUNDING_RADAR_CACHE_DIR`, `FUNDING_RADAR_CACHE_TTL` (seconds), or disable it with `FUNDING_RADAR_CACHE=false`.

The project defaults to `REPORT_MODE=production` through mise, which writes the committed weekly report to `_reports/YYYY-Www.md`. For local development, use `mise set REPORT_MODE=development` or run `REPORT_MODE=development bundle exec ruby bin/generate_report`; this writes the mutable report to the ignored `_reports/latest.md`.

To generate a report for a specific date:

```sh
REPORT_DATE=2026-07-11 bundle exec ruby bin/generate_report
```

To include local fixture opportunities alongside live portal results:

```sh
INCLUDE_FIXTURES=true bundle exec ruby bin/generate_report
```

LLM-assisted summaries are opt-in and configured per source in `data/llm_processing.yml`. The normal report remains deterministic. To run a local LLM report, set the global enable switch, provider key, and processing mode:

```sh
FUNDING_RADAR_LLM=enabled GEMINI_API_KEY=... REPORT_PROCESSING=source_config bundle exec ruby bin/generate_report
```

Use `REPORT_PROCESSING=both` to generate the deterministic report and a marked `*-llm-comparison.md` review report. Set `FUNDING_RADAR_LLM=disabled` to override every source setting and stop all model calls immediately. Successful summaries are cached in the committed `data/llm_cache/` directory and are invalidated when the source content, prompt version, model, or schema changes.

To inspect the live EU Funding & Tenders source without writing a report:

```sh
bundle exec ruby bin/check_eu_source --year 2026 --limit 20
```

To inspect the live Portugal 2030 workbook source without writing a report:

```sh
bundle exec ruby bin/check_portugal_2030_source --limit 20
```

To inspect the live European Urban Initiative catalogue without writing a report:

```sh
bundle exec ruby bin/check_european_urban_initiative_source --raw --limit 20
```

## GitHub Actions

The workflow in `.github/workflows/pages.yml`:

- runs weekly on Monday morning
- supports manual `workflow_dispatch`
- installs Ruby and Node dependencies
- runs the Ruby test suite
- generates the weekly report
- commits generated `_reports` changes only when changes exist
- builds Tailwind CSS and Jekyll
- deploys `_site` to GitHub Pages

## Enable GitHub Pages

In the GitHub repository settings:

1. Open **Settings > Pages**.
2. Set **Build and deployment** to **GitHub Actions**.
3. Run the workflow manually once, or wait for the weekly schedule.

The workflow needs repository write permission so it can commit newly generated reports.

## Add A New Funding Source

Add a source adapter under `lib/funding_radar/sources`.

The adapter should expose `#fetch` and return normalized `FundingRadar::Opportunity` objects. Prefer official APIs, feeds, CSV files, JSON endpoints, or published machine-readable data. Avoid scraping and browser automation unless no official alternative exists.

After adding the adapter:

1. Add tests for the adapter.
2. Register it in `bin/generate_report`.
3. Add a `bin/check_<source>_source` debugging script that can inspect the live/raw source without writing a report.
4. Ensure duplicate handling still produces one record per real opportunity.

The scoring, report generation, and Jekyll templates should not need source-specific changes.

The Portugal 2030 adapter reads the official open-data workbook linked from the [annual notice plan](https://portugal2030.pt/plano-anual-de-avisos/). It follows the workbook’s current `.xlsx` link, keeps planned opening and closing dates, links each normalized opportunity back to the official plan, and currently retains notices applicable to Lisboa/AML, nationwide or extra-regional notices, and multi-region notices that explicitly include AML. Lisboa 2030 is not a separate adapter because its programme rows and AML opportunities are already present in this workbook.

The Interreg Sudoe adapter reads the official open-call index and linked call pages, currently importing the 3rd and 4th 2026 calls with their deadlines, budgets, partnership requirements, and municipal themes.

The Turismo de Portugal adapter reads the official current-notices listing and enriches each notice from its linked detail page where available. It keeps open/current entries, extracts published deadlines, amounts and applicant signals, and treats detail-page failures as non-fatal.

## Funding Source Roadmap

Use this checklist to track the source suggestions from the project’s funding-source shortlist. Before implementation, confirm that each candidate publishes actual funding calls through an official, stable source and is relevant to Portuguese local authorities.

| Source | Status | Difficulty | Official source | Data format | Municipal relevance | Overlap | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EU Funding & Tenders | Done | Medium | [Funding & Tenders](https://ec.europa.eu/info/funding-tenders/opportunities/portal/) | Public search API | High for eligible EU projects | Baseline | Existing API adapter; covers Erasmus+, LIFE, CERV, and Creative Europe records where available. |
| Portugal 2030 | Done | Easy | [Annual notice plan](https://portugal2030.pt/plano-anual-de-avisos/) | Official XLSX plus portal listings | High, with current AML/nationwide/multi-region scope | Baseline | Existing adapter retains Lisboa/AML, nationwide, extra-regional, and multi-region notices including AML. |
| Lisboa 2030 | Covered by Portugal 2030 | — | [Lisboa 2030 notices](https://lisboa.portugal2030.pt/avisos/) | Same official annual-plan XLSX | High for AML municipalities | Duplicate of Portugal 2030 for the current radar scope | The central workbook already includes `LISBOA2030` and `AML` rows. Revisit only if regional detail is published there that is absent from the central plan. |
| Turismo de Portugal | Done | Easy | [Candidaturas e avisos](https://business.turismodeportugal.pt/pt/Investir/Financiamento/avisos-concursos/Paginas/default.aspx) | Stable HTML listing and linked notices; no public feed/API found | Low to medium; mainly tourism companies/private promoters, with occasional public-sector relevance | High for Portugal 2030 notices | Adapter reads current listing entries and best-effort linked notice details; eligibility remains notice-specific. |
| Interreg Sudoe | Done | Medium | [Official calls](https://interreg-sudoe.eu/en/las-convocatorias-sudoe-ya-estan-abiertas/call/) | Official HTML pages plus PDF/DOCX call kits; eSudoe2127 is a private submission application; no public API/feed found | Medium to high for municipalities able to join transnational partnerships across Portugal, Spain and southwest France | Low to medium; distinct Interreg programme, though thematic EU overlap is possible | Adapter imports current open calls with deadlines, budgets, partnership requirements and links to the official call pages. Authentication is required to submit, not to read calls. |
| European Urban Initiative | Done | Medium | [EUI call catalogue](https://portico.urban-initiative.eu/urban-panorama/call-for-proposals) and [EUI site](https://www.urban-initiative.eu/) | Stable official HTML catalogue with status/deadline/support/amount fields and linked call documents; no public API/feed found | Very high for urban authorities and cities; municipalities are explicit eligible applicants for Innovative Actions and related calls | Low; distinct ERDF urban initiative, not normally a Funding & Tenders or Portugal 2030 notice | Adapter imports open and upcoming catalogue entries, including eligibility, deadline and funding support where published; closed calls are omitted. |
| IPDJ | Not suitable | Medium | [IPDJ candidaturas](https://ipdj.gov.pt/candidaturas) | Official HTML programme pages and online forms; no public API/feed found | Low for municipalities/juntas as direct applicants; mostly associations, clubs, federations and youth organisations | Low; mostly outside existing sources | It publishes real calls, but eligibility is narrowly organisation-based and an official sports-prize notice explicitly excludes local authorities. Keep as a manual signpost only if the product later expands to local partner organisations. |
| FCT | Not suitable | Medium | [myFCT calls](https://outsystems.fct.pt/MyFCT/) and [FCT contests](https://www.fct.pt/concursos/) | Dynamic official call catalogue; detailed PDFs and myFCT authenticated submission; no public feed/API found | Low as a direct municipal source; primarily researchers, SNCT institutions and R&D consortia | Some thematic overlap with EU Funding & Tenders, but different national research funding | Actual calls are published, but direct municipal eligibility is uncommon and requires notice-by-notice interpretation. Dynamic rendering, login and document-heavy details make it poor for the current static radar. |
| LEADER | Viable — later | Hard | [PEPAC GAL and contests](https://pepacc.pt/leader/) | Central official HTML territory/GAL directory and contest pages; individual GAL sites and PDF notices; no common public API/feed found | Medium in rural territories; direct eligibility varies and many calls target farms/SMEs, though public/local partners can be relevant | Low to medium; PEPAC/LEADER is distinct, but rural calls can resemble Portugal 2030 local-development opportunities | The PEPAC site currently maps 52 GALs, territories and available contests, so discovery is possible. The blocker is heterogeneous GAL content, changing links and notice-by-notice eligibility; scheduled static generation would need a central-first strategy plus fallbacks. |
| BPI / Fundação “la Caixa” | Not suitable | Medium | [BPI Fundação “la Caixa” awards](https://www.bancobpi.pt/sustentabilidade/compromisso-social/premios-bpi-fundacao-la-caixa) | Official HTML pages and PDF regulations; authenticated proprietary application platform; no public feed/API found | Low as a direct source: 2026 awards require private non-profit institutions, not municipalities or juntas | None material with current public-funds sources | Real annual grant competitions (Infância, Solidário, Seniores, Capacitar), with 2026 awards up to €150,000, but eligibility and platform access exclude the target public bodies. Keep out unless partner-organisation funding is later in scope. |
| ANAFRE | Not suitable | Medium | [ANAFRE](https://www.anafre.pt/) and [Botija Solidária guidance](https://www.anafre.pt/fundo-ambiental-bilha-botija-solidaria/) | Official HTML/PDF guidance and separate authenticated operational platforms; no public call feed/API found | Low as a funding-call source; high only as operational information for freguesias implementing a specific aid scheme | Often relays or operationalises other public programmes rather than adding separate funding | It publishes institutional information, training/inscriptions and programme guidance. The 2026 Botija Solidária page is an implementation workflow for freguesias and citizens, not a competitive funding call. Remove as a roadmap adapter unless the product scope expands to administrative programme alerts. |

## Current Limitations

- The EU Funding & Tenders source uses the public portal search API and filters for topic-detail records; the portal does not provide a small, formally documented grants-only API in this project yet.
- Fixture data remains available for tests, demos, and development without network access.
- Scoring is deterministic and based on explicit eligibility and thematic signals.
- Deadlines and eligibility still require manual confirmation in official documentation.
- The project does not send alerts or emails.

## Future Improvements

- Add deeper EU Funding & Tenders topic-detail enrichment if a stable official detail endpoint is identified.
- Add official source adapters for LIFE, Erasmus+, and CERV where separate programme APIs are available.
- Add stronger deadline status labels and filters.
- Add historical change detection between weekly reports.
- Add optional LLM-assisted summarization and relevance explanations behind the existing scorer interface.
