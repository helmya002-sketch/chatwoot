# Tolzar: the open-source notices shown on the in-app "Open-source licences" page (profile menu). The licence
# compliance of the product lives here, not on the marketing site.
#   foundation  the inbox foundation's MIT notice (LICENSE at the app root)
#   gems        every gem the running app loaded through Bundler, with the licence files the gem ships
#   javascript  the packages in the browser bundles, written at image build by docker/tolzar/js_notices.mjs
#   system      the image's Alpine packages (/lib/apk/db/installed) plus Ruby and libvips (built from source)
#   ai          the brain's Python packages (config/tolzar/brain_notices.json, tools/brain_notices.py in
#               the brain repo) and its runtime, plus the model and model server the running brain is
#               configured with (GET /notices/ai, read live and cached for MODELS_TTL, so it cannot drift)
# Components under a weak-copyleft licence (LGPL, MPL, EPL, CDDL) are also listed in `source_offer` with
# where their source code is published. Everything but the live model list is built once per process: it
# only changes with a deploy.
class Tolzar::OpenSourceNotices
  LICENCE_FILE = /\A(licen[cs]e|copying|notice|mit-licen[cs]e|unlicen[cs]e)(\.|-|\z)/i
  WEAK_COPYLEFT = /LGPL|MPL|Mozilla Public|EPL|Eclipse Public|CDDL|Lesser General/i
  MAX_TEXT = 64.kilobytes
  APK_DB = '/lib/apk/db/installed'.freeze
  JS_FILE = Rails.root.join('config/tolzar/js_notices.json')
  BRAIN_FILE = Rails.root.join('config/tolzar/brain_notices.json')
  VIPS_SOURCE = 'https://github.com/libvips/libvips/releases'.freeze
  MODELS_TTL = 5.minutes

  # The brain image is python:3.12-slim (Debian). The model and its server are not listed here: they come
  # from the running brain (live_models).
  AI_RUNTIME = [
    { name: 'Python', version: '3.12', licences: ['PSF-2.0'], homepage: 'https://docs.python.org/3/license.html' },
    { name: 'Debian base system (brain image)', version: '12', licences: ['various, incl. LGPL-2.1 (glibc)'],
      homepage: 'https://sources.debian.org' }
  ].freeze
  MODELS_UNAVAILABLE = { name: 'AI model (the list is unavailable right now; reload later)', version: '', licences: [],
                         homepage: '', role: 'production' }.freeze

  def self.call(account_id = nil)
    base = (@base ||= new.call)
    ai = base[:groups][:ai] + live_models(account_id)
    base.merge(groups: base[:groups].merge(ai: ai), counts: base[:counts].merge(ai: ai.size))
  end

  # The models the brain answers with, cached for MODELS_TTL; a failed read is not cached.
  def self.live_models(account_id)
    return @models if @models && @models_at > MODELS_TTL.ago

    items = new.brain_models(account_id)
    return [MODELS_UNAVAILABLE] if items.empty?

    @models_at = Time.current
    @models = items
  end

  def self.reset!
    @base = @models = @models_at = nil
  end

  def call
    groups = { gems: gems, javascript: json_items(JS_FILE), system: system, ai: json_items(BRAIN_FILE) + AI_RUNTIME }
    { foundation: foundation, groups: groups, source_offer: source_offer(groups), counts: groups.transform_values(&:size) }
  end

  def brain_models(account_id)
    res = Tolzar::BrainClient.get('/notices/ai', account_id: account_id.to_i)
    return [] unless res.is_a?(Hash) && res['status'] == 200

    Array(res['items']).map do |i|
      { name: i['name'].to_s, version: i['version'].to_s, licences: Array(i['licences']).map(&:to_s),
        homepage: i['homepage'].to_s, role: i['role'].to_s }
    end
  rescue StandardError
    []
  end

  private

  def foundation
    { name: 'Chatwoot (inbox foundation)', licences: ['MIT'], homepage: 'https://github.com/chatwoot/chatwoot',
      text: read(Rails.root.join('LICENSE')) }
  end

  def gems
    Bundler.load.specs.sort_by { |s| [s.name, s.version] }.map do |spec|
      { name: spec.name, version: spec.version.to_s, licences: Array(spec.licenses).presence || ['UNKNOWN'],
        homepage: spec.homepage.to_s, author: Array(spec.authors).join(', '), text: licence_text(spec.full_gem_path) }
    end
  end

  def system
    apk_packages + [
      { name: 'Ruby', version: RUBY_VERSION, licences: ['Ruby OR BSD-2-Clause'], homepage: 'https://www.ruby-lang.org/en/about/license.txt' },
      { name: 'libvips', version: vips_version, licences: ['LGPL-2.1-or-later'], homepage: VIPS_SOURCE }
    ]
  end

  def apk_packages
    return [] unless File.readable?(APK_DB)

    File.read(APK_DB).split(/\n\n+/).filter_map do |block|
      f = block.lines.to_h { |l| [l[0, 2], l[2..].to_s.strip] }
      next if f['P:'].blank?

      { name: f['P:'], version: f['V:'].to_s, licences: [f['L:'].presence || 'UNKNOWN'], homepage: f['U:'].to_s }
    end
  end

  def vips_version
    defined?(Vips) ? Vips.version_string : ''
  rescue StandardError
    ''
  end

  def json_items(file)
    return [] unless File.readable?(file)

    Array(JSON.parse(File.read(file))['items']).map do |i|
      { name: i['name'].to_s, version: i['version'].to_s, licences: Array(i['licences']), homepage: i['homepage'].to_s,
        author: i['author'].to_s, text: i['text'].to_s[0, MAX_TEXT] }
    end
  rescue JSON::ParserError
    []
  end

  def source_offer(groups)
    groups.values.flatten.select { |i| i[:licences].join(' ').match?(WEAK_COPYLEFT) }
          .map { |i| i.slice(:name, :version, :licences, :homepage) }
  end

  def licence_text(dir)
    return '' if dir.blank? || !Dir.exist?(dir)

    Dir.children(dir).sort.select { |f| f.match?(LICENCE_FILE) && File.file?(File.join(dir, f)) }
       .map { |f| read(File.join(dir, f)) }.join("\n\n")
  end

  def read(path)
    File.read(path, MAX_TEXT, encoding: 'UTF-8').to_s.scrub
  rescue StandardError
    ''
  end
end
