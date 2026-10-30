xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.rss version: '2.0', 'xmlns:atom' => 'http://www.w3.org/2005/Atom' do
  xml.channel do
    xml.title t('tolzar.feedback.changelog.feed_title')
    xml.link tolzar_feedback_changelog_url
    xml.description t('tolzar.feedback.changelog.intro')
    xml.language I18n.locale.to_s
    xml.tag! 'atom:link', href: tolzar_feedback_changelog_url(format: :rss), rel: 'self', type: 'application/rss+xml'
    @entries.each do |entry|
      url = tolzar_feedback_changelog_url(anchor: entry.anchor)
      xml.item do
        xml.title entry.title
        xml.link url
        xml.guid url, isPermaLink: 'true'
        xml.pubDate entry.published_at.rfc2822
        xml.description entry.body_html
      end
    end
  end
end
