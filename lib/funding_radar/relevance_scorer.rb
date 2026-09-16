module FundingRadar
  class RelevanceScorer
    MUNICIPAL_TERMS = [
      "autoridades locais",
      "autarquias",
      "municípios",
      "municipios",
      "juntas de freguesia",
      "entidades públicas",
      "entidades publicas",
      "administração pública",
      "administracao publica",
      "local authorities",
      "local/regional authorities",
      "municipalities",
      "public authorities",
      "urban authorities"
    ].freeze

    THEME_WEIGHTS = {
      "civic_participation" => 6,
      "accessibility" => 5,
      "inclusion" => 5,
      "equality" => 5,
      "mobility" => 5,
      "climate" => 4,
      "environment" => 4,
      "volunteering" => 4,
      "public_space" => 5,
      "digital_public_services" => 6,
      "community_development" => 6
    }.freeze
    LOCAL_IMPACT_PATTERNS = [
      /\blocal authorit(?:y|ies)\b/, /\bmunicipal(?:ity|ities)?\b/, /\bcities\b/, /\burban\b/,
      /\bcommunities\b/, /\bneighbou?rhoods?\b/, /\bpublic services?\b/, /\bregional development\b/,
      /\bautoridades locais\b/, /\bmunicípios\b/, /\bmunicipios\b/, /\bautarquias\b/,
      /\bcidades\b/, /\burbano\b/, /\bcomunidades\b/, /\bserviços públicos\b/, /\bservicos publicos\b/,
      /\bpolíticas locais\b/, /\bpoliticas locais\b/, /\blocal policy\b/
    ].freeze
    PUBLIC_POLICY_PATTERNS = [
      /\bpublic polic(?:y|ies)\b/, /\bpolicy[- ]?makers?\b/, /\bgovernance\b/, /\bpublic sector\b/,
      /\bpolíticas públicas\b/, /\bpoliticas publicas\b/, /\bgovernação\b/, /\bgovernacao\b/
    ].freeze
    PUBLIC_INTEREST_PATTERNS = [
      /\bcompetenc(?:e|es|y|ies)\b/, /\bskills?\b/, /\beducation(?:al)?\b/, /\bhealth(?:care)?\b/,
      /\bhousing\b/, /\bpoverty\b/, /\bcitizenship\b/, /\byouth\b/, /\bcare services?\b/,
      /\bigualdade\b/, /\beducação\b/, /\beducacao\b/, /\bsaúde\b/, /\bsaude\b/,
      /\bhabitação\b/, /\bhabitacao\b/, /\bpobreza\b/, /\bjuventude\b/, /\bcuidados?\b/
    ].freeze
    THEME_CAP = 18
    LOCAL_IMPACT_POINTS = 15
    PUBLIC_POLICY_POINTS = 10
    PUBLIC_INTEREST_POINTS = 15
    STRATEGIC_TRANSITION_PATTERN = /\bgreen transition\b/
    STRATEGIC_TRANSITION_POINTS = 5
    BASE_SCORE = 10
    LOCAL_AUTHORITY_POINTS = 45
    PUBLIC_BODY_POINTS = 25
    LISBON_TERMS = /\b(?:aml|lisboa|lisbon|lisboa2030)\b/i
    LISBON_BONUS = 8

    Result = Data.define(:score, :category, :explanation)

    def score(opportunity, today: Date.today)
      score = BASE_SCORE
      reasons = []

      if eligible_local_authority?(opportunity)
        score += LOCAL_AUTHORITY_POINTS
        reasons << "aceita autarquias ou entidades públicas como candidatas"
      elsif eligible_public_body?(opportunity)
        score += PUBLIC_BODY_POINTS
        reasons << "aceita entidades públicas como candidatas"
      else
        reasons << "a elegibilidade das autarquias deve ser confirmada"
      end

      impact_text = opportunity_text(opportunity)
      if LOCAL_IMPACT_PATTERNS.any? { |pattern| impact_text.match?(pattern) }
        score += LOCAL_IMPACT_POINTS
        reasons << "tem impacto explícito em comunidades, cidades ou serviços locais"
      end
      if PUBLIC_POLICY_PATTERNS.any? { |pattern| impact_text.match?(pattern) }
        score += PUBLIC_POLICY_POINTS
        reasons << "tem aplicação em políticas públicas ou governação"
      end
      if PUBLIC_INTEREST_PATTERNS.any? { |pattern| impact_text.match?(pattern) }
        score += PUBLIC_INTEREST_POINTS
        reasons << "incide em necessidades de interesse público"
      end
      if impact_text.match?(STRATEGIC_TRANSITION_PATTERN)
        score += STRATEGIC_TRANSITION_POINTS
        reasons << "contribui para uma transição estratégica"
      end

      theme_points = matched_theme_names(opportunity).sum { |theme| THEME_WEIGHTS.fetch(theme) }
      if theme_points.positive?
        score += [theme_points, THEME_CAP].min
        reasons << "incide em temas relevantes para políticas locais"
      end

      if lisbon_relevant?(opportunity)
        score += LISBON_BONUS
        reasons << "tem incidência territorial em Lisboa ou na Área Metropolitana de Lisboa"
      end

      days = days_until_deadline(opportunity, today)
      if days && days <= 21
        score += 8
        reasons << "tem prazo próximo"
      elsif days && days <= 60
        score += 4
        reasons << "tem janela de preparação curta"
      end

      score = [[score, 0].max, 100].min

      Result.new(
        score: score,
        category: category_for(score),
        explanation: explanation_for(score, reasons)
      )
    end

    private

    def eligible_local_authority?(opportunity)
      text = opportunity.eligible_applicants.join(" ").downcase
      MUNICIPAL_TERMS.any? { |term| text.include?(term) }
    end

    def eligible_public_body?(opportunity)
      text = opportunity.eligible_applicants.join(" ").downcase
      text.match?(/\b(?:public|públic|publica|pública)\b/) || text.include?("entidades públicas")
    end

    def opportunity_text(opportunity)
      [opportunity.title, opportunity.summary, opportunity.other_requirements].compact.join(" ").downcase
    end

    def lisbon_relevant?(opportunity)
      [opportunity.programme, opportunity.title, opportunity.summary, opportunity.other_requirements].join(" ").match?(LISBON_TERMS)
    end

    def matched_theme_names(opportunity)
      opportunity.themes.select { |theme| THEME_WEIGHTS.key?(theme) }
    end

    def days_until_deadline(opportunity, today)
      deadline = opportunity.deadline_date
      return nil unless deadline

      (deadline - today).to_i
    end

    def category_for(score)
      case score
      when 75..100 then "Altamente relevante"
      when 50..74 then "A investigar"
      else "Prioridade baixa"
      end
    end

    def explanation_for(score, reasons)
      return "A oportunidade pode ser relevante, mas faltam sinais fortes nos dados disponíveis." if reasons.empty?
      return "Prioridade baixa: faltam sinais fortes de elegibilidade ou alinhamento municipal nos dados disponíveis." if score < 50

      "Esta oportunidade é relevante porque #{reasons.uniq.join(", ")}."
    end

  end
end
