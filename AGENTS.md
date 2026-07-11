# Agent Notes

## Project

EU Funding Radar is a static Ruby/Jekyll/Tailwind site for weekly funding intelligence aimed at Portuguese local authorities.

Do not convert this into Rails, add a database, or add a backend server. Keep the project static and GitHub Pages compatible.

## Core Commands

Run tests:

```sh
bundle exec rake test
```

Build CSS:

```sh
npm run build:css
```

Build the site:

```sh
bundle exec jekyll build
```

Generate the weekly report from live EU Funding & Tenders data:

```sh
bundle exec ruby bin/generate_report
```

Inspect the live EU source without writing a report:

```sh
bundle exec ruby bin/check_eu_source --year 2026 --limit 20
```

## Funding Sources

The default source is `FundingRadar::Sources::EuFundingTendersSource`.

Fixture data exists in `data/sources/fixtures.yml`, but normal report generation must not include it. Fixtures are opt-in only:

```sh
INCLUDE_FIXTURES=true bundle exec ruby bin/generate_report
```

Tests should not depend on live network calls. Use recorded/minimal payloads and fake HTTP clients.

## EU Funding & Tenders Notes

The official no-JavaScript topic index is mostly historical, so the source falls back to structured programme/year search terms such as `HORIZON-NEB-2026`, `LIFE-2026`, `CERV-2026`, and `ERASMUS-SPORT-2026`.

The EC search API can return noisy records such as FAQs and organisations. The source should normalize only Funding & Tenders topic records and skip closed calls where the payload exposes closed status.

Prefer the API's English results (`language=en`). If a topic has only explicitly non-English records, omit it rather than publishing a translated title or summary. When the API returns no language metadata, retain the record and prefer the richest available topic payload.

Many topic records do not expose deadlines reliably. Preserve `nil` deadlines and let the report show "Por confirmar".

Budget data may be nested in `budgetOverview`/`budgetTopicActionMap`, including total topic budgets and maximum contributions per project. Normalize these into readable euro amounts, and leave the amount blank when no numeric budget is available.

## Verification Expectations

Before finishing source, report, or template changes, run:

```sh
bundle exec rake test
npm run build:css
bundle exec jekyll build
```

If report generation is changed, confirm the generated report contains only live-source records unless `INCLUDE_FIXTURES=true` is explicitly used.

## Git

This repo uses `main`. Keep generated weekly reports in `_reports/` committed so the archive is durable.
