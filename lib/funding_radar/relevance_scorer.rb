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
      "administracao publica"
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

    Result = Data.define(:score, :category, :explanation, :suggested_next_step)

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
        explanation: explanation_for(reasons),
        suggested_next_step: next_step_for(score, days)
      )
    end

    private

    def eligible_local_authority?(opportunity)
      text = opportunity.eligible_applicants.join(" ").downcase
      MUNICIPAL_TERMS.any? { |term| text.include?(term) }
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

    def explanation_for(reasons)
      return "A oportunidade pode ser relevante, mas faltam sinais fortes nos dados disponíveis." if reasons.empty?

      "Esta oportunidade é relevante porque #{reasons.uniq.join(", ")}."
    end

    def next_step_for(score, days)
      if score >= 75
        "Ler o aviso oficial, confirmar elegibilidade e identificar rapidamente uma equipa responsável."
      elsif days && days <= 21
        "Confirmar requisitos essenciais antes de investir tempo, porque o prazo está próximo."
      elsif score >= 50
        "Analisar o aviso e decidir se existe projeto municipal ou de freguesia alinhado."
      else
        "Guardar para referência e reavaliar se surgirem parceiros ou enquadramento mais favorável."
      end
    end
  end
end
