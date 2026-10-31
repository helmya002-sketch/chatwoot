# Tolzar lead sources (TikTok plan row 8, the part that needs no ad API): leads per source and campaign, with how
# many reached the won and lost stages (the pipeline's last two stages, Tolzar::PipelineSettings). The source comes
# from Tolzar::LeadIntake and Tolzar::AdAttribution (contact custom attributes lead_source / lead_campaign). Ad spend
# and cost per lead join later from the ad platforms' reporting APIs. Read-only.
class Tolzar::LeadSources
  WINDOWS = [7, 30, 90, 365].freeze

  def initialize(account, days: 90)
    @account = account
    @days = WINDOWS.include?(days.to_i) ? days.to_i : 90
  end

  def rows
    stages = Tolzar::PipelineSettings.stage_keys(@account)
    won, lost = stages.last(2)
    attr = Tolzar::PipelineSettings::STAGE_ATTRIBUTE
    scope = @account.contacts.where(created_at: @days.days.ago..).where("custom_attributes->>'lead_source' IS NOT NULL")
    grouped = scope.group(Arel.sql("custom_attributes->>'lead_source'"), Arel.sql("custom_attributes->>'lead_campaign'"),
                          Arel.sql("custom_attributes->>'#{attr}'")).count
    table = Hash.new { |h, k| h[k] = { leads: 0, won: 0, lost: 0 } }
    grouped.each do |(source, campaign, stage), count|
      row = table[[source.to_s, campaign.to_s]]
      row[:leads] += count
      row[:won] += count if stage == won
      row[:lost] += count if stage == lost
    end
    table.map { |(source, campaign), r| { source: source, campaign: campaign.presence, **r } }
         .sort_by { |r| [-r[:leads], r[:source], r[:campaign].to_s] }
  end

  def view
    { ok: true, days: @days, rows: rows }
  end
end
