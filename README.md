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
5. A dated ISO-week report is written to `_reports/YYYY-Www.md`.
6. Jekyll renders the homepage, individual report pages, and archive.

By default, the first implementation loads fixture data from `data/sources/fixtures.yml`.

To generate a report for a specific date:

```sh
REPORT_DATE=2026-07-11 bundle exec ruby bin/generate_report
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

## Current Limitations

- The initial version uses fixture data and does not yet call live funding APIs.
- Scoring is deterministic and based on explicit eligibility and thematic signals.
- Deadlines and eligibility still require manual confirmation in official documentation.
- The project does not send alerts or emails.

## Future Improvements

- Add official source adapters for EU Funding & Tenders Portal, Portugal 2030, Lisboa 2030, Interreg, LIFE, Erasmus+, and CERV.
- Add stronger deadline status labels and filters.
- Add historical change detection between weekly reports.
- Add optional LLM-assisted summarization and relevance explanations behind the existing scorer interface.
