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

Build the local Web Awesome components used by the report filters:

```sh
npm run build:js
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

Inspect the live Portugal 2030 source without writing a report:

```sh
bundle exec ruby bin/check_portugal_2030_source --limit 20
```

## Funding Sources

The default sources are `FundingRadar::Sources::EuFundingTendersSource` and `FundingRadar::Sources::Portugal2030Source`.

The Portugal 2030 adapter reads the official annual-plan XLSX workbook. It retains Lisboa/AML opportunities, multi-region opportunities that explicitly include AML, and nationwide or extra-regional opportunities; it excludes notices limited to other regions. It must not depend on live calls in tests.

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
npm run build:js
bundle exec jekyll build
```

## Frontend Filter Notes

The report theme filter uses locally bundled Web Awesome components. Keep the Web Awesome assets self-hosted; do not replace them with a CDN runtime dependency.

Theme keys such as `climate` and `community_development` are canonical internal IDs used by scoring and source normalization. Portuguese labels and URL-safe query slugs are maintained in `_data/theme_labels.yml`. Shared filter URLs use repeated `tema` parameters, for example `?tema=clima&tema=inclusao`; the JavaScript continues to read legacy English `theme` parameters for compatibility.

The date filters and theme filters are client-side only, preserve their state in the URL, and must continue to work on static GitHub Pages without a backend.

The source filter is also client-side only and uses repeated Portuguese `fonte` parameters, for example `?fonte=Portugal%202030`; legacy `source` parameters remain readable for compatibility.

If report generation is changed, confirm the generated report contains only live-source records unless `INCLUDE_FIXTURES=true` is explicitly used.

## Git

This repo uses `main`. Keep generated weekly reports in `_reports/` committed so the archive is durable.
