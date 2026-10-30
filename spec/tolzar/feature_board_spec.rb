require 'rails_helper'

# Tolzar: the public feature-request board, roadmap and changelog (owner-approved community plan, 30 Oct 2026).
# Reading is public; posting, voting and commenting need the dashboard login and a workspace; the plan's spam
# rules; super admin statuses, merges and the changelog; the shipped email; the public JSON.
RSpec.describe 'Tolzar feature board', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:author) { create(:user, account: account) }
  let(:member) { create(:user, account: account) }
  let(:super_admin) { create(:super_admin) }
  let(:env) do
    { FRONTEND_URL: 'https://app.example.test', NEWSLETTER_FROM: 'Tolzar <news@news.example.test>',
      NEWSLETTER_SMTP_DOMAIN: 'news.example.test', NEWSLETTER_POSTAL_ADDRESS: 'Example Street 1, Hurghada' }
  end
  let(:idea) do
    Tolzar::Idea.create!(title: 'Snooze a conversation until Monday', body: 'So weekend messages wait for the team.',
                         locale: 'en', tag: 'inbox', user: author, account: account).tap { |i| i.votes.create!(user: author) }
  end

  around { |example| with_modified_env(env) { example.run } }

  before { Redis::Alfred.scan_each(match: 'tolzar:feedback:*') { |key| Redis::Alfred.delete(key) } }

  def sign_in_dashboard(user)
    token = user.create_new_auth_token
    cookies['cw_d_session_info'] = { 'access-token' => token['access-token'], 'client' => token['client'], 'uid' => token['uid'] }.to_json
  end

  def human_params(extra = {})
    { form_token: Tolzar::FeedbackFormToken.issue(5.seconds.ago), website: '' }.merge(extra)
  end

  def post_idea(title: 'Export contacts to CSV', body: 'For the monthly report.')
    post '/feedback', params: human_params(idea: { title: title, body: body, tag: 'contacts', locale: 'en' })
  end

  describe 'reading' do
    it 'is public: board, roadmap, changelog, RSS and the idea page, all noindex' do
      idea.update!(status: 'planned')
      entry = Tolzar::ChangelogEntry.create!(title: 'October release', body_markdown: 'New **snooze**.', published_at: 1.hour.ago)
      idea.update!(changelog_entry: entry)

      get '/feedback'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(idea.title).and include('<meta name="robots" content="noindex">')

      get '/feedback/roadmap'
      expect(response.body).to include(idea.title)

      get "/feedback/#{idea.to_param}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<title>#{idea.title} — Planned | Tolzar feature requests</title>")
      expect(response.body).to include('rel="canonical" href="https://app.example.test/feedback/')
      expect(response.body).to include('"@type":"DiscussionForumPosting"')

      get '/feedback/changelog'
      expect(response.body).to include('October release').and include(idea.title)
      get '/feedback/changelog.rss'
      expect(response.media_type).to eq('application/rss+xml')
      expect(response.body).to include('<title>October release</title>')
    end

    it 'redirects an old slug to the canonical URL and hides held or hidden ideas from others' do
      get "/feedback/#{idea.id}-old-title"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/feedback/#{idea.to_param}")

      idea.update!(held: true)
      get "/feedback/#{idea.to_param}"
      expect(response).to have_http_status(:not_found)
      sign_in_dashboard(author)
      get "/feedback/#{idea.to_param}"
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'voting' do
    it 'needs a login and a workspace' do
      post "/feedback/#{idea.to_param}/vote"
      expect(response).to have_http_status(:unauthorized)

      sign_in_dashboard(create(:user))
      post "/feedback/#{idea.to_param}/vote"
      expect(response).to have_http_status(:forbidden)
      expect(idea.reload.votes_count).to eq(1)
    end

    it 'gives one vote per user; voting again takes it back' do
      sign_in_dashboard(member)
      post "/feedback/#{idea.to_param}/vote"
      expect(idea.reload.votes_count).to eq(2)
      post "/feedback/#{idea.to_param}/vote"
      expect(idea.reload.votes_count).to eq(1)
      expect(Tolzar::IdeaVote.where(idea: idea, user: member)).to be_empty

      idea.votes.create!(user: member)
      expect { idea.votes.create!(user: member) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'allows 30 votes an hour' do
      sign_in_dashboard(member)
      30.times { post "/feedback/#{idea.to_param}/vote" }
      expect(response).to have_http_status(:redirect)
      post "/feedback/#{idea.to_param}/vote"
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'posting' do
    before { sign_in_dashboard(member) }

    it 'holds an account first post, shown only to its author, and adds the author vote' do
      post_idea
      posted = Tolzar::Idea.last
      expect(posted).to have_attributes(held: true, user_id: member.id, account_id: account.id, votes_count: 1)
      expect(Tolzar::Idea.on_board).not_to include(posted)

      get "/feedback/#{posted.to_param}"
      expect(response).to have_http_status(:ok)

      posted.approve!
      post_idea(title: 'A second idea')
      expect(Tolzar::Idea.last.held).to be(false)
    end

    it 'holds a first comment too and refuses links until a post is approved' do
      post "/feedback/#{idea.to_param}/comments", params: human_params(comment: { body: 'Same here' })
      expect(Tolzar::IdeaComment.last).to have_attributes(held: true, user_id: member.id)

      post "/feedback/#{idea.to_param}/comments", params: human_params(comment: { body: 'See https://spam.example' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Tolzar::IdeaComment.count).to eq(1)

      Tolzar::IdeaComment.last.approve!
      post "/feedback/#{idea.to_param}/comments", params: human_params(comment: { body: 'Docs: https://docs.example' })
      expect(Tolzar::IdeaComment.last).to have_attributes(held: false, body: 'Docs: https://docs.example')
    end

    it 'refuses a filled honeypot and a submit faster than 3 seconds' do
      post '/feedback', params: human_params(website: 'http://bot.example', idea: { title: 'Bot', body: 'Bot', locale: 'en' })
      expect(response).to have_http_status(:unprocessable_entity)
      post '/feedback', params: { form_token: Tolzar::FeedbackFormToken.issue, website: '', idea: { title: 'Bot', body: 'Bot', locale: 'en' } }
      expect(response).to have_http_status(:unprocessable_entity)
      post '/feedback', params: { website: '', idea: { title: 'Bot', body: 'Bot', locale: 'en' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Tolzar::Idea.count).to eq(0)
    end

    it 'allows 5 posts an hour, ideas and comments together' do
      4.times { |n| post_idea(title: "Idea #{n}") }
      post "/feedback/#{idea.to_param}/comments", params: human_params(comment: { body: 'Fifth post' })
      expect(response).to have_http_status(:redirect)
      post_idea(title: 'Sixth')
      expect(response).to have_http_status(:too_many_requests)
      expect(Tolzar::Idea.where(user: member).count).to eq(4)
    end

    it 'shadow-hides a post at 2 reports from different users until a moderator approves it' do
      idea
      post "/feedback/#{idea.to_param}/report"
      post "/feedback/#{idea.to_param}/report"
      expect(idea.reload.reports_count).to eq(1)
      expect(Tolzar::Idea.on_board).to include(idea)

      sign_in_dashboard(create(:user, account: account))
      post "/feedback/#{idea.to_param}/report"
      expect(Tolzar::Idea.on_board).not_to include(idea)

      idea.reload.approve!
      expect(Tolzar::Idea.on_board).to include(idea)
    end
  end

  describe 'super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'shows the page with the moderation queue' do
      idea.update!(held: true)
      get '/super_admin/feedback'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(idea.title)
    end

    it 'changes a status only with an explanation: dated history plus the pinned staff comment' do
      post "/super_admin/feedback/change_status?id=#{idea.id}", params: { status: 'planned', explanation: '' }
      expect(idea.reload.status).to eq('under_review')

      post "/super_admin/feedback/change_status?id=#{idea.id}", params: { status: 'planned', explanation: 'Next quarter.' }
      post "/super_admin/feedback/change_status?id=#{idea.id}", params: { status: 'building', explanation: 'Started.' }
      expect(idea.reload.status).to eq('building')
      expect(idea.status_changes.order(:created_at).pluck(:from_status, :to_status)).to eq([%w[under_review planned], %w[planned building]])
      expect(idea.pinned_comment).to have_attributes(body: 'Started.', staff: true, user_id: super_admin.id)
      expect(idea.comments.where(pinned: true).count).to eq(1)
    end

    it 'merges a duplicate: votes carried over once per user, both authors told' do
      dup_author = create(:user, account: account)
      duplicate = Tolzar::Idea.create!(title: 'Snooze until a date', body: 'Same', locale: 'en', user: dup_author)
      [dup_author, member].each { |u| duplicate.votes.create!(user: u) }
      idea.votes.create!(user: member) # member voted on both: counted once

      expect { post "/super_admin/feedback/merge_idea?id=#{duplicate.id}", params: { into_id: idea.id } }
        .to have_enqueued_job(Tolzar::FeatureBoardNotifyJob).with('merged', duplicate.id)
      expect(idea.reload.votes_count).to eq(3)
      expect(idea.votes.pluck(:user_id)).to contain_exactly(author.id, member.id, dup_author.id)
      expect(duplicate.reload).to have_attributes(merged_into_id: idea.id, votes_count: 0)

      with_modified_env(env.merge(NEWSLETTER_ENABLED: 'true')) do
        expect { Tolzar::FeatureBoardNotifyJob.perform_now('merged', duplicate.id) }.to change(ActionMailer::Base.deliveries, :count).by(2)
      end
    end

    it 'writes a changelog entry linked to its ideas' do
      post '/super_admin/feedback/save_changelog',
           params: { changelog_entry: { title: 'Snooze is here', body_markdown: 'Details' }, idea_ids: idea.id.to_s, publish: '1' }
      entry = Tolzar::ChangelogEntry.last
      expect(entry.published_at).to be_present
      expect(idea.reload.changelog_entry).to eq(entry)
    end
  end

  describe 'notify on ship' do
    it 'emails each voter once, in their language, skips opted-out users, and only with NEWSLETTER_ENABLED' do
      idea.votes.create!(user: member)
      opted_out = create(:user, account: account)
      idea.votes.create!(user: opted_out)
      Tolzar::NewsletterRecipient.opt_out!(opted_out.id)
      member.update!(ui_settings: { 'locale' => 'es' })

      expect { idea.change_status!(to: 'shipped', explanation: 'Released today.', by: super_admin) }
        .to have_enqueued_job(Tolzar::FeatureBoardNotifyJob).with('shipped', idea.id).on_queue('low')

      expect { Tolzar::FeatureBoardNotifyJob.perform_now('shipped', idea.id) }.not_to change(ActionMailer::Base.deliveries, :count)

      with_modified_env(env.merge(NEWSLETTER_ENABLED: 'true')) do
        expect { Tolzar::FeatureBoardNotifyJob.perform_now('shipped', idea.id) }.to change(ActionMailer::Base.deliveries, :count).by(2)
        expect(ActionMailer::Base.deliveries.last(2).flat_map(&:to)).to contain_exactly(author.email, member.email)
        spanish = ActionMailer::Base.deliveries.last(2).find { |m| m.to == [member.email] }
        expect(spanish.subject).to eq("Disponible: #{idea.title}")
        expect(spanish.text_part.body.decoded).to include('Released today.')

        idea.change_status!(to: 'building', explanation: 'One more fix.', by: super_admin)
        idea.change_status!(to: 'shipped', explanation: 'Released again.', by: super_admin)
        expect { Tolzar::FeatureBoardNotifyJob.perform_now('shipped', idea.id) }.not_to change(ActionMailer::Base.deliveries, :count)
      end
    end
  end

  describe 'public JSON' do
    it 'lists the roadmap and changelog with no names or emails, cacheable for 5 minutes' do
      idea.update!(status: 'planned')
      entry = Tolzar::ChangelogEntry.create!(title: 'October release', body_markdown: 'Notes', published_at: 1.hour.ago)
      idea.update!(changelog_entry: entry)

      get '/feedback/roadmap.json'
      expect(response.headers['Cache-Control']).to include('public').and include('max-age=300')
      planned = response.parsed_body['statuses'].find { |s| s['status'] == 'planned' }
      expect(planned['ideas']).to eq([{ 'id' => idea.id, 'title' => idea.title, 'votes' => 1,
                                        'url' => "https://app.example.test/feedback/#{idea.to_param}" }])

      expect(response.body).not_to include(author.email, author.name)

      get '/feedback/changelog.json'
      expect(response.parsed_body['entries'].first).to include('title' => 'October release')
      expect(response.parsed_body['entries'].first['ideas'].first.keys).to contain_exactly('id', 'title', 'votes', 'url')
      expect(response.body).not_to include(author.email, author.name)
    end
  end
end
