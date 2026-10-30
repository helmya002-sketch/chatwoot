# Tolzar: a workspace's pipeline, generic for any business. Its stages, which contact attributes hold
# the stage (first filled wins), which one holds a deal's value, and the currency that value is in.
# Stored in account.settings (the dashboard reads them from the account JSON, tolzarStages.js);
# an Owner sets them in Settings > Pipeline. Nothing here is tied to one workspace.
class Tolzar::PipelineSettings
  KEYS = %w[pipeline_stages stage_attributes deal_value_attribute deal_currency].freeze
  TONES = %w[slate amber iris teal ruby].freeze
  ATTRIBUTE = /\A[a-z0-9_]{1,60}\z/
  CURRENCY = /\A[A-Z]{3}\z/

  # The stage list when the workspace has none (the same defaults as tolzarStages.js DEFAULT_STAGES), and
  # the contact attribute a stage change writes (the Pipeline board and the contact pane write this one).
  DEFAULT_STAGE_KEYS = ['New Lead', 'Active', 'Offer Sent Follow up', 'Customer Won', 'Customer Lost'].freeze
  STAGE_ATTRIBUTE = 'lifecycle_stage'.freeze

  Result = Struct.new(:values, :errors)

  def self.view(account)
    (account.settings || {}).slice(*KEYS)
  end

  # The workspace's stage keys, in order (saved through validate, so each stage is a {key, label, tone} hash).
  def self.stage_keys(account)
    Array((account.settings || {})['pipeline_stages']).filter_map { |stage| stage['key'] if stage.is_a?(Hash) }.presence ||
      DEFAULT_STAGE_KEYS
  end

  # Only the keys sent are checked and returned; an empty value clears that key (back to the default).
  def self.validate(params)
    new(params.is_a?(Hash) ? params.to_h.stringify_keys : {}).validate
  end

  def initialize(params)
    @params = params
    @errors = []
    @values = {}
  end

  def validate
    stages if @params.key?('pipeline_stages')
    stage_attributes if @params.key?('stage_attributes')
    deal_value_attribute if @params.key?('deal_value_attribute')
    deal_currency if @params.key?('deal_currency')
    Result.new(@values, @errors)
  end

  private

  def stages
    list = Array(@params['pipeline_stages'])
    return @values['pipeline_stages'] = nil if list.empty?

    @errors << 'pipeline_stages: between 2 and 12 stages' unless list.size.between?(2, 12)
    out = list.first(12).each_with_index.map { |raw, i| stage(raw, i) }.compact
    @errors << 'pipeline_stages: each stage needs its own name' if out.map { |s| s['key'] }.uniq.size != list.first(12).size
    @values['pipeline_stages'] = out
  end

  def stage(raw, index)
    item = raw.is_a?(Hash) ? raw.stringify_keys : { 'key' => raw }
    key = item['key'].to_s.strip.first(60)
    return nil if key.blank?

    label = item['label'].to_s.strip.first(40).presence || key
    tone = TONES.include?(item['tone'].to_s) ? item['tone'].to_s : TONES[index % TONES.size]
    { 'key' => key, 'label' => label, 'tone' => tone }
  end

  def stage_attributes
    list = Array(@params['stage_attributes']).map { |k| k.to_s.strip }.compact_blank.uniq
    return @values['stage_attributes'] = nil if list.empty?

    @errors << 'stage_attributes: up to 4 attribute keys (a-z, 0-9, _)' if list.size > 4 || list.any? { |k| !k.match?(ATTRIBUTE) }
    @values['stage_attributes'] = list.first(4)
  end

  def deal_value_attribute
    key = @params['deal_value_attribute'].to_s.strip
    @errors << 'deal_value_attribute: an attribute key (a-z, 0-9, _)' if key.present? && !key.match?(ATTRIBUTE)
    @values['deal_value_attribute'] = key.presence
  end

  def deal_currency
    code = @params['deal_currency'].to_s.strip.upcase
    @errors << 'deal_currency: a 3-letter currency code, like EUR or USD' if code.present? && !code.match?(CURRENCY)
    @values['deal_currency'] = code.presence
  end
end
