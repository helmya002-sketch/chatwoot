# Tolzar booking documents: a period's issued and cancelled documents as one .tar.gz (plan §1 "export: the register
# as CSV, plus the PDFs"), built with Ruby's own tar writer and zlib (no new gem). Each PDF is rendered by the brain
# (POST /documents/render); if the renderer is not available nothing is sent, so an archive is never half empty.
require 'rubygems/package'

class Tolzar::DocumentArchive
  Refused = Class.new(StandardError)
  MAX_DOCUMENTS = 100

  def initialize(account, from: nil, to: nil)
    @account = account
    @from = parse(from) || 30.days.ago.to_date
    @to = parse(to) || Date.current
  end

  def build
    docs = Tolzar::Document.where(account_id: @account.id, status: %w[issued void], issued_at: @from.beginning_of_day..@to.end_of_day)
                           .includes(:contact).order(:issued_at).limit(MAX_DOCUMENTS).to_a
    files = docs.map { |d| ["#{d.number}.pdf", render(d)] }
    files << ['register.csv', register(docs)]
    { data: tar_gz(files), filename: "documents-#{@from.iso8601}-#{@to.iso8601}.tar.gz", count: docs.size }
  end

  private

  def parse(value)
    Date.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def render(document)
    branding = Tolzar::DocumentBranding.for_render(@account, document.doc_type)
    res = Tolzar::BrainClient.post('/documents/render', { document: document.view, branding: branding }, account_id: @account.id)
    raise Refused, 'the PDF renderer is not available right now' unless res['status'] == 200

    Base64.strict_decode64(res['pdf_b64'].to_s)
  end

  def register(docs)
    CSV.generate do |out|
      out << %w[number type status contact total currency issued_at void_reason]
      docs.each do |d|
        out << [d.number, d.doc_type, d.status, d.contact&.name, format('%.2f', d.total_cents / 100.0), d.currency,
                d.issued_at&.utc&.iso8601, d.void_reason]
      end
    end
  end

  def tar_gz(files)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    Gem::Package::TarWriter.new(gz) do |tar|
      files.each do |name, data|
        tar.add_file_simple(name.to_s.gsub(%r{[^\w.-]}, '_'), 0o644, data.bytesize) { |f| f.write(data) }
      end
    end
    gz.close
    io.string
  end
end
