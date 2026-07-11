require "date"

module FundingRadar
  Opportunity = Data.define(
    :id,
    :title,
    :programme,
    :deadline,
    :funding_source,
    :official_link,
    :eligible_applicants,
    :partnership_requirements,
    :summary,
    :themes
  ) do
    def self.from_hash(hash)
      data = hash.transform_keys(&:to_sym)

      new(
        id: data.fetch(:id),
        title: data.fetch(:title),
        programme: data.fetch(:programme),
        deadline: data[:deadline],
        funding_source: data.fetch(:funding_source),
        official_link: data.fetch(:official_link),
        eligible_applicants: Array(data[:eligible_applicants]),
        partnership_requirements: data[:partnership_requirements].to_s,
        summary: data.fetch(:summary),
        themes: Array(data[:themes]).map(&:to_s)
      )
    end

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
  end
end
