require 'rails_helper'

# TikTok plan row 6: the ad that started a chat is kept on the conversation and, once, on the lead.
RSpec.describe Tolzar::AdAttribution do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:payload) { { 'referral' => { 'ad_id' => 'ad-7', 'campaign_id' => 'cmp-2', 'campaign_name' => 'Spring sale' } } }

  it 'keeps the ad on the conversation and tags a contact without a source' do
    described_class.record(conversation: conversation, contact: contact, payload: payload, platform: 'tiktok')
    expect(conversation.reload.additional_attributes['tolzar_ad']).to include('ad_id' => 'ad-7', 'campaign_id' => 'cmp-2',
                                                                               'platform' => 'tiktok')
    expect(contact.reload.custom_attributes).to include('lead_source' => 'tiktok_ad', 'lead_campaign' => 'Spring sale',
                                                        'lead_ad' => 'ad-7')
  end

  it "keeps the first ad and never overwrites a contact's source" do
    contact.update!(custom_attributes: { 'lead_source' => 'website' })
    described_class.record(conversation: conversation, contact: contact, payload: payload, platform: 'tiktok')
    other = { 'ad_info' => { 'ad_id' => 'ad-9' } }
    described_class.record(conversation: conversation, contact: contact, payload: other, platform: 'tiktok')
    expect(conversation.reload.additional_attributes.dig('tolzar_ad', 'ad_id')).to eq('ad-7')
    expect(contact.reload.custom_attributes['lead_source']).to eq('website')
  end

  it 'does nothing without an ad in the payload' do
    described_class.record(conversation: conversation, contact: contact, payload: { 'type' => 'text' }, platform: 'tiktok')
    expect(conversation.reload.additional_attributes).not_to have_key('tolzar_ad')
  end
end
