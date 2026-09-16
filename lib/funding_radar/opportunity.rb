require "date"

module FundingRadar
  Opportunity = Data.define(
    :id,
    :title,
    :programme,
    :opening_date,
    :deadline,
    :funding_amount,
    :funding_source,
    :source_key,
    :official_link,
    :document_link,
    :eligible_applicants,
    :partnership_requirements,
    :other_requirements,
    :summary,
    :themes,
    :geography
  ) do
    def self.from_hash(hash)
      data = hash.transform_keys(&:to_sym)

      new(
        id: data.fetch(:id),
        title: data.fetch(:title),
        programme: data.fetch(:programme),
        opening_date: data[:opening_date],
        deadline: data[:deadline],
        funding_amount: data[:funding_amount].to_s,
        funding_source: data.fetch(:funding_source),
        source_key: data[:source_key].to_s,
        official_link: data.fetch(:official_link),
        document_link: data[:document_link].to_s,
        eligible_applicants: Array(data[:eligible_applicants]),
        partnership_requirements: data[:partnership_requirements].to_s,
        other_requirements: data[:other_requirements].to_s,
        summary: data.fetch(:summary),
        themes: Array(data[:themes]).map(&:to_s).uniq,
        geography: normalize_geography(data[:geography])
      )
    end

    def applicant_eligibility_status
      eligible_applicants.empty? ? "unknown" : "known"
    end

    def self.normalize_geography(value)
      return {"scope" => "unknown", "areas" => []} unless value.is_a?(Hash)

      scope = value[:scope] || value["scope"]
      areas = value[:areas] || value["areas"]
      return {"scope" => "unknown", "areas" => []} unless %w[local regional national transnational eu unknown].include?(scope.to_s)

      {"scope" => scope.to_s, "areas" => Array(areas).map(&:to_s).reject(&:empty?).uniq}
    end
    private_class_method :normalize_geography

    def duplicate_key
      return official_link.to_s.strip.downcase unless official_link.to_s.strip.empty?

      "#{programme}-#{title}".downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
    end

    def deadline_date
      return nil if deadline.to_s.strip.empty?

      Date.iso8601(deadline.to_s)
    rescue Date::Error
      nil
    end

    def opening_date_value
      return nil if opening_date.to_s.strip.empty?

      Date.iso8601(opening_date.to_s)
    rescue Date::Error
      nil
    end
  end
end
