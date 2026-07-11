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
      "civic_participation" => 12,
      "accessibility" => 10,
      "inclusion" => 10,
      "equality" => 10,
      "mobility" => 9,
      "climate" => 10,
      "environment" => 10,
      "volunteering" => 7,
      "public_space" => 9,
      "digital_public_services" => 9,
      "community_development" => 10
    }.freeze
    LISBON_TERMS = /\b(?:aml|lisboa|lisbon|lisboa2030)\b/i
    LISBON_BONUS = 8

    Result = Data.define(:score, :category, :explanation)

    def score(opportunity, today: Date.today)
      score = 20
      reasons = []

      if eligible_local_authority?(opportunity)
        score += 30
        reasons << "aceita autarquias ou entidades públicas como candidatas"
      else
        reasons << "a elegibilidade das autarquias deve ser confirmada"
      end

      matched_theme_names(opportunity).each do |theme|
        score += THEME_WEIGHTS.fetch(theme)
      end

      if lisbon_relevant?(opportunity)
        score += LISBON_BONUS
        reasons << "tem incidência territorial em Lisboa ou na Área Metropolitana de Lisboa"
      end

      unless matched_theme_names(opportunity).empty?
        reasons << "incide em temas relevantes para políticas locais"
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
