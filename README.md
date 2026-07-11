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

By default, report generation queries the official EU Funding & Tenders Portal search API and the official Portugal 2030 annual notice plan workbook, normalizing both into the same opportunity model. Fixture data remains available for local fallback and demos.

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

To inspect the live EU Funding & Tenders source without writing a report:

```sh
bundle exec ruby bin/check_eu_source --year 2026 --limit 20
```

To inspect the live Portugal 2030 workbook source without writing a report:

```sh
bundle exec ruby bin/check_portugal_2030_source --limit 20
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
3. Ensure duplicate handling still produces one record per real opportunity.

The scoring, report generation, and Jekyll templates should not need source-specific changes.

The Portugal 2030 adapter reads the official open-data workbook linked from the [annual notice plan](https://portugal2030.pt/plano-anual-de-avisos/). It follows the workbook’s current `.xlsx` link, keeps planned opening and closing dates, links each normalized opportunity back to the official plan, and currently retains notices applicable to Lisboa/AML, nationwide or extra-regional notices, and multi-region notices that explicitly include AML.

## Current Limitations

- The EU Funding & Tenders source uses the public portal search API and filters for topic-detail records; the portal does not provide a small, formally documented grants-only API in this project yet.
- Fixture data remains available for tests, demos, and development without network access.
- Scoring is deterministic and based on explicit eligibility and thematic signals.
- Deadlines and eligibility still require manual confirmation in official documentation.
- The project does not send alerts or emails.

## Future Improvements

- Add deeper EU Funding & Tenders topic-detail enrichment if a stable official detail endpoint is identified.
- Add official source adapters for Portugal 2030, Lisboa 2030, Interreg, LIFE, Erasmus+, and CERV where separate programme APIs are available.
- Add stronger deadline status labels and filters.
- Add historical change detection between weekly reports.
- Add optional LLM-assisted summarization and relevance explanations behind the existing scorer interface.
