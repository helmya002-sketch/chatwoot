# Tolzar (roadmap A5): "Export workspace". Everything one account holds, so a customer can
# leave with their data. Ruby stdlib only (tar + gzip): no new dependency.
#   contacts.csv, conversations.jsonl (with messages), inboxes/teams/labels/attributes.json,
#   brain.json (the AI brain's export: agents, workflows, decisions, audit; never tokens).
# Kept 7 days as an ActiveStorage blob, then purged.
# H4: an export is found only through the blob ids this job recorded on the account
# (internal_attributes['tolzar_exports']) and its server-set metadata, never by filename:
# anyone who can upload a file (e.g. a widget visitor) chooses its filename.
# H1 (full-sec): each recorded export carries a random download token; the download is looked up
# by token + account, never by the (sequential, guessable) blob id. Old id links stop working.
# M6 (full-sec): contacts.csv cells that a spreadsheet would run as a formula are prefixed with '.
require 'csv'
require 'rubygems/package'
require 'zlib'

class Tolzar::WorkspaceExportJob < ApplicationJob
  queue_as :low
  KEEP = 7.days

  EXPORTS_KEY = 'tolzar_exports'.freeze # [{ 'id' => blob id, 'token' => download token }]
  LEGACY_IDS_KEY = 'tolzar_export_blob_ids'.freeze # pre-H1 id-only list: purged on the next export
  FORMULA_START = /\A[=+\-@\uFF20\t\r]/

  def self.prefix(account_id) = "tolzar-export-#{account_id}-"

  def self.entries(account_id)
    Array(Account.find(account_id).internal_attributes[EXPORTS_KEY]).select do |e|
      e.is_a?(Hash) && e['id'].present? && e['token'].is_a?(String) && e['token'].present?
    end
  end

  def self.blobs(account_id)
    ActiveStorage::Blob.where(id: entries(account_id).map { |e| e['id'] }).order(created_at: :desc)
  end

  # { blob id => token } for this account's recorded exports.
  def self.tokens(account_id) = entries(account_id).to_h { |e| [e['id'], e['token']] }

  # The recorded export blob whose token matches, or nil. Never a lookup by id from the request.
  def self.find_by_token(account_id, token)
    token = token.to_s
    return if token.blank?

    entry = entries(account_id).find { |e| ActiveSupport::SecurityUtils.secure_compare(e['token'], token) }
    entry && ActiveStorage::Blob.find_by(id: entry['id'])
  end

  # A spreadsheet runs a cell starting with = + - @ (or fullwidth @, tab, CR) as a formula.
  def self.csv_safe(value)
    value.is_a?(String) && value.match?(FORMULA_START) ? "'#{value}" : value
  end

  def self.export_blob?(blob, account_id)
    blob.present? && blob.metadata['tolzar_export'] == true && blob.metadata['account_id'] == account_id
  end

  def perform(account_id)
    account = Account.find(account_id)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    Gem::Package::TarWriter.new(gz) do |tar|
      add(tar, 'contacts.csv', contacts_csv(account))
      add(tar, 'conversations.jsonl', conversations_jsonl(account))
      add(tar, 'inboxes.json', account.inboxes.map { |i| { id: i.id, name: i.name, channel_type: i.channel_type } }.to_json)
      add(tar, 'teams.json', account.teams.map { |t| { id: t.id, name: t.name, members: t.members.map(&:email) } }.to_json)
      add(tar, 'labels.json', account.labels.map { |l| { title: l.title, description: l.description, color: l.color } }.to_json)
      add(tar, 'custom_attribute_definitions.json', account.custom_attribute_definitions.to_json)
      add(tar, 'brain.json', Tolzar::BrainClient.get("/export?account_id=#{account.id}", account_id: account.id).to_json)
      add(tar, 'README.txt', "Tolzar workspace export of account #{account.id} (#{account.name}), #{Time.current.utc.iso8601}.\n")
    end
    gz.close
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(io.string), content_type: 'application/gzip',
      filename: "#{self.class.prefix(account.id)}#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.tar.gz",
      metadata: { tolzar_export: true, account_id: account.id }
    )
    record(account, blob)
  end

  private

  def record(account, blob)
    expired = self.class.blobs(account.id).where('created_at < ?', KEEP.ago).to_a
    legacy = ActiveStorage::Blob.where(id: Array(account.internal_attributes[LEGACY_IDS_KEY])).to_a
                                .select { |b| self.class.export_blob?(b, account.id) }
    account.with_lock do
      gone = expired.map(&:id)
      kept = self.class.entries(account.id).reject { |e| gone.include?(e['id']) }
      attrs = account.internal_attributes.except(LEGACY_IDS_KEY)
      account.update!(internal_attributes: attrs.merge(
        EXPORTS_KEY => kept + [{ 'id' => blob.id, 'token' => SecureRandom.urlsafe_base64(24) }]
      ))
    end
    (expired + legacy).each(&:purge_later)
  end

  def add(tar, name, data)
    data = data.to_s.b
    tar.add_file_simple(name, 0o644, data.bytesize) { |f| f.write(data) }
  end

  def contacts_csv(account)
    CSV.generate do |csv|
      csv << %w[id name email phone_number identifier created_at additional_attributes custom_attributes]
      account.contacts.find_each do |c|
        csv << [c.id, c.name, c.email, c.phone_number, c.identifier, c.created_at&.utc&.iso8601,
                c.additional_attributes.to_json, c.custom_attributes.to_json].map { |v| self.class.csv_safe(v) }
      end
    end
  end

  def conversations_jsonl(account)
    out = +''
    account.conversations.includes(:messages).find_each do |conv|
      out << {
        id: conv.id, display_id: conv.display_id, inbox_id: conv.inbox_id, contact_id: conv.contact_id,
        status: conv.status, created_at: conv.created_at&.utc&.iso8601, labels: conv.label_list,
        custom_attributes: conv.custom_attributes, team_id: conv.team_id, assignee_id: conv.assignee_id,
        messages: conv.messages.sort_by(&:id).map do |m|
          { id: m.id, created_at: m.created_at&.utc&.iso8601, message_type: m.message_type, private: m.private,
            sender_type: m.sender_type, content: m.content, content_attributes: m.content_attributes }
        end
      }.to_json << "\n"
    end
    out
  end
end
