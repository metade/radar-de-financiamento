# Funding Radar skill evaluations

Run each prompt in an imported/enabled skill session. The expected behaviour describes observable checks, not a fixed answer: current API contents and dates may change.

## 1. Climate and public space (Portuguese)

> Somos uma Junta de Freguesia em Lisboa. Queremos plantar árvores, criar mais sombra e melhorar os parques infantis. Há financiamentos a que nos possamos candidatar?

Expected: fetch `meta.json` and `catalog.json`; interpret the project across climate adaptation, urban heat, trees, public space, environment, and children; prioritise plausible Lisbon/local-authority candidates; fetch details; state eligibility certainty and geography; include official links and deadline/status.

## 2. Accessibility (Portuguese)

> Somos uma Junta de Freguesia e queremos melhorar a acessibilidade dos nossos edifícios públicos.

Expected: find genuinely accessibility-related opportunities and inspect details. Do not promote a call merely because accessibility appears as a weak incidental theme. Qualify uncertain applicant or geography information.

## 3. Digital participation (Portuguese)

> Queremos criar uma plataforma digital para participação cívica local. Existem financiamentos relevantes?

Expected: search semantically across civic participation, digital public services, democracy, digital inclusion, and community development, not just literal “plataforma digital”; shortlist a few plausible calls and verify details.

## 4. Unknown applicant eligibility

> Somos uma associação local e procuramos financiamento para um projecto comunitário. Que oportunidades devemos investigar?

Expected: when a candidate has `applicant_eligibility_status: unknown` or no eligible-applicant list, explicitly say Funding Radar has not confirmed whether the association is eligible. Never call it eligible because it appears in the catalogue.

## 5. Unknown geography

> Somos uma organização em Lisboa e queremos desenvolver um projecto de inclusão social. Que avisos parecem relevantes?

Expected: if a candidate has `facts.geography.scope: unknown` and no areas, say geography is unestablished. Do not claim that the opportunity applies in Portugal or Lisbon solely from that unknown value.

## 6. Deadline and status

> Encontre oportunidades abertas para uma autarquia e diga quais exigem atenção imediata aos prazos.

Expected: use API `status` and ISO `deadline`; prominently flag imminent deadlines; do not recommend `closed` or past-deadline records as currently available; label missing/unknown deadlines as “Por confirmar” or unknown.

## 7. English

> We are a Lisbon-based non-profit working on digital inclusion. What current funding opportunities should we investigate?

Expected: answer naturally in English while using the same metadata → catalogue → detail workflow, semantic matching, conservative eligibility/geography language, freshness, deadlines, and authoritative source links.

