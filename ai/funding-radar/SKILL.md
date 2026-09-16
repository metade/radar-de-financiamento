---
name: funding-radar
description: Find and explain potentially relevant funding opportunities for Portuguese municipalities, parish councils, public bodies, and organisations using the live Funding Radar static API. Use for funding discovery, comparison, and applicant-fit questions; do not treat it as an eligibility decision or application service.
---

# Funding Radar

Use Funding Radar as a specialist discovery and analysis dataset for funding questions. Work in the language used by the user (Portuguese or English). Search first with the context already provided; ask a follow-up only when a missing fact materially changes the search.

## Public API

Base URL: `https://radar-de-financiamento.decidimosarroios.pt`

- `https://radar-de-financiamento.decidimosarroios.pt/api/v1/meta.json` — API version, refresh time, and counts.
- `https://radar-de-financiamento.decidimosarroios.pt/api/v1/catalog.json` — compact discovery index.
- `https://radar-de-financiamento.decidimosarroios.pt/api/v1/schema.json` — JSON Schema for detail records.
- `https://radar-de-financiamento.decidimosarroios.pt/api/v1/opportunities/{id}.json` — one detailed record; substitute the catalogue `id` exactly.

These are ordinary periodically generated static JSON files. There is no request-time search or live eligibility decision. If this ChatGPT surface cannot retrieve arbitrary public HTTP/JSON URLs, say so plainly and ask the user to provide the relevant JSON or use a surface with web access; never invent current results.

## Retrieval workflow

1. Extract what is known: applicant type, location/geography, project idea, subject areas, approximate budget, timing, and partnership constraints. Interpret the project semantically. For example, shade at playgrounds can involve climate adaptation, urban heat, trees, public space, environment, children, or community infrastructure; a digital participation platform can involve civic participation, democracy, digital public services, digital inclusion, or community development.
2. Fetch `meta.json` first. Use `generated_at` to state how fresh the dataset is. Do not call it live; flag unexpectedly stale data.
3. Fetch `catalog.json` for discovery. Use title, programme, summary, themes, applicants, `applicant_eligibility_status`, geography, deadline, and status together. Shortlist roughly 3–5 strong candidates when they exist; return fewer when evidence is weak.
4. Fetch each promising candidate’s detail URL before making a confident recommendation. Read the relevant `facts`, `analysis`, `provenance`, and `links` fields, including funding amounts, applicant types, geography, partnership and other requirements, dates, source organisation, and official links.
5. Where an official source or document URL is present, link it for every recommended opportunity and tell the user to verify the call documentation before acting.

## Interpret the JSON conservatively

The detail shape is:

- identity: top-level `id`, `title`, `programme`, `status`;
- source-derived facts: `facts.opening_date`, `facts.deadline`, `facts.funding_amount`, `facts.eligible_applicants`, `facts.applicant_eligibility_status`, `facts.partnership_requirements`, `facts.other_requirements`, `facts.themes`, and `facts.geography`;
- Funding Radar analysis: `analysis.summary`, optional `relevance_score`, `relevance_category`, `relevance_explanation`, and optional `llm_analysis`;
- provenance: `provenance.source_organisation`, `source_reference_id`, `report_generated_at`, and date-source fields;
- authoritative links: `links.source_url` and optional `links.document_url`.

Catalogue entries flatten discovery fields and add `detail_url` and `source_url`. The catalogue normally contains only records with `status` `open` or `unknown`; a detail record may still be `closed` because historical opportunities remain available. `status` is `open`, `closed`, or `unknown`. A missing/invalid deadline produces `unknown`, not open-ended availability.

Themes are enriched discovery hints, not official criteria. A matching theme does not establish eligibility, and an absent theme does not by itself rule an opportunity out. Low-information summaries such as “Resumo limitado; consultar a documentação oficial da oportunidade.” are fallbacks: do not infer meaning from them.

### Eligibility

`facts.applicant_eligibility_status` is either `known` or `unknown`.

- `known` means Funding Radar has populated `eligible_applicants`; it is not a guarantee that the user qualifies in every respect.
- `unknown` or a missing/empty applicant list means Funding Radar has not established eligibility. It never means eligible. Say explicitly: “Funding Radar has not confirmed whether [organisation] is eligible; check the official call.”
- Distinguish “possibly relevant”, “apparently fits the listed applicant type”, and “confirmed by the official call”. Prefer the official source when conditions matter. Do not treat `analysis.llm_analysis.eligibility` as authoritative.

### Geography

Read `facts.geography.scope` (`local`, `regional`, `national`, `transnational`, `eu`, or `unknown`) and `facts.geography.areas`. An explicit Área Metropolitana de Lisboa/AML match is useful for a Lisbon applicant. `scope: unknown` with empty areas means the restriction has not been established; it does not mean Portugal-wide or Lisbon-wide availability.

### Dates and funding conditions

Use ISO dates as supplied and compare both dates with today: a future `opening_date` should be described as upcoming/not yet open even if `status` is `open` (the API status is deadline-based). Do not present `closed` or past-deadline opportunities as currently available. Mention an imminent deadline prominently. A nil/unknown deadline must be reported as “deadline/status unknown” or “Por confirmar”, not as unlimited time. Never fill in missing amount, funding rate, co-financing, partnership, exclusions, or procedure. If a requirement says to confirm in the official notice, preserve that uncertainty.

## Facts versus analysis

Treat identity, dates, amounts, applicant lists, geography, requirements, provenance, and links as source-derived only to the extent the record labels or represents them that way. Treat `analysis.summary`, themes, relevance explanations/scores, suggested interpretations, and `llm_analysis` as Funding Radar guidance. Do not attribute generated wording to the funding authority. Do not expose internal report/debug/cache details.

## Answer format

Give a useful shortlist rather than dumping records. For each candidate, explain:

- why the project may fit;
- applicant fit and its certainty;
- geography and its certainty;
- status/deadline (and urgency);
- funding amount only when present;
- partnership or other watch-outs;
- the official source link.

End with a short comparison/conclusion and concrete verification steps. Do not assign a new numerical score. You may mention Funding Radar’s existing relevance score/category only if useful or requested, and label it as Funding Radar analysis. Do not provide legal advice, guaranteed eligibility, guaranteed funding, completed applications, or authoritative interpretations of programme rules.
