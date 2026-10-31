require 'rails_helper'

# Tolzar's own help (round 4, c67): /tz/help/<topic> opens our help-centre article (found by title), or the help
# centre's home when there is none; it never leaves our host. Every feature help link is one of these topics.
RSpec.describe 'Tolzar help topics', type: :request do
  let(:account) { create(:account) }
  let(:author) { create(:user, account: account, role: :administrator) }
  let!(:portal) { create(:portal, account: account, slug: 'help') }

  it 'opens the published article for a topic' do
    article = create(:article, portal: portal, account: account, author: author, locale: 'en',
                               title: 'Roles: Owner, Manager, Agent', status: :published)
    get '/tz/help/roles'
    expect(response).to redirect_to("/hc/help/articles/#{article.slug}")
  end

  it 'opens the help centre home for a topic without a published article, or an unknown topic' do
    create(:article, portal: portal, account: account, author: author, locale: 'en',
                     title: 'Broadcasts', status: :draft)
    get '/tz/help/broadcasts'
    expect(response).to redirect_to('/hc/help/en')
    get '/tz/help/no_such_topic'
    expect(response).to redirect_to('/hc/help/en')
  end

  it 'points every feature help link at one of our topics, never at Chatwoot' do
    urls = YAML.safe_load(Rails.root.join('config/feature_help_urls.yml').read).values
    urls += YAML.safe_load(Rails.root.join('config/features.yml').read).filter_map { |f| f['help_url'] }
    expect(urls).not_to be_empty
    urls.each do |url|
      topic = url.delete_prefix('/tz/help/')
      expect(url).to start_with('/tz/help/')
      expect(Tolzar::HelpTopics::TOPICS).to have_key(topic)
    end
  end
end
