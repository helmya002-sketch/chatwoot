require 'rails_helper'

# Never depend on Chatwoot (owner rule, 29 Oct; round 4, c68): no link to, and no call to, a Chatwoot-run host
# (chatwoot.com and its subdomains, chatwoot.help, chatwoot.app, the chwt.app short links) anywhere in what we ship.
# Test fixtures, stories and built bundles are not shipped code and are left out. E-mail addresses are not URLs.
RSpec.describe 'Tolzar: no Chatwoot links or calls' do
  let(:chatwoot_url) { %r{https?://([a-z0-9-]+\.)*(chatwoot\.(com|help|app)|chwt\.app)\b}i }
  let(:shipped) { %w[app lib config public] }
  let(:text_files) { %w[.rb .erb .js .vue .ts .yml .yaml .json .scss .css .html .md .rake .liquid .haml] }
  let(:not_shipped) { %r{(/spec/|/specs/|fixtures|\.story\.|/story/|\Apublic/(vite|packs|assets)[^/]*/)} }

  it 'has no Chatwoot URL in shipped code' do
    offenders = shipped.flat_map { |dir| Dir.glob(Rails.root.join(dir, '**', '*')) }.filter_map do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      next if File.directory?(path) || relative.match?(not_shipped) || !text_files.include?(File.extname(path))

      text = File.read(path, encoding: 'UTF-8', invalid: :replace, undef: :replace)
      line = text.each_line.with_index(1).find { |l, _| l.match?(chatwoot_url) }
      "#{relative}:#{line.last}: #{line.first.strip.first(120)}" if line
    end
    expect(offenders).to be_empty, "Chatwoot URLs found:\n#{offenders.join("\n")}"
  end

  it 'knows a Chatwoot URL from an e-mail address or our own links' do
    expect('see https://chwt.app/hc/x').to match(chatwoot_url)
    expect('https://hub.2.chatwoot.com/ping').to match(chatwoot_url)
    expect('support@chatwoot.com').not_to match(chatwoot_url)
    expect('/tz/help/roles').not_to match(chatwoot_url)
  end
end
