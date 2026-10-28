require 'rails_helper'
require 'vips'

# Licence work: libvips in the image is built without libimagequant/fftw (GPL). Avatar and attachment
# thumbnails must still be generated. Server ops also runs `rails tolzar:verify_image_variants` in the image.
RSpec.describe 'Tolzar image variants (libvips)' do
  let(:samples) { Tolzar::ImageVariantCheck.samples }
  let(:thumbnail) { Tolzar::ImageVariantCheck::THUMBNAIL }

  def read_variant(variant)
    Vips::Image.new_from_buffer(variant.processed.download, '')
  end

  it 'transforms PNG, JPEG and GIF samples with the configured variant processor' do
    expect(ActiveStorage.variant_processor).to eq(:vips)
    expect(Tolzar::ImageVariantCheck.run!).to all(end_with('ok'))
  end

  it 'turns GIF thumbnails into PNG, since this libvips has no GIF saver' do
    expect(ActiveStorage.web_image_content_types).to eq(%w[image/png image/jpeg])
  end

  it 'processes contact avatars the way avatar_url requests them' do
    contact = create(:contact)
    contact.avatar.attach(io: StringIO.new(samples['image/jpeg']), filename: 'avatar.jpg', content_type: 'image/jpeg')

    image = read_variant(contact.avatar.representation(thumbnail))
    expect(image.get('vips-loader')).to start_with('jpegload')
    expect(image.width).to be_between(1, 250)
    expect(contact.avatar_url).to be_present
  end

  it 'processes a GIF avatar into a PNG thumbnail' do
    contact = create(:contact)
    contact.avatar.attach(io: StringIO.new(samples['image/gif']), filename: 'avatar.gif', content_type: 'image/gif')

    expect(read_variant(contact.avatar.representation(thumbnail)).get('vips-loader')).to start_with('pngload')
  end

  it 'processes image attachment thumbnails the way thumb_url requests them' do
    message = create(:message)
    attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
    attachment.file.attach(io: StringIO.new(samples['image/png']), filename: 'photo.png', content_type: 'image/png')
    message.save!

    image = read_variant(attachment.file.representation(thumbnail))
    expect(image.get('vips-loader')).to start_with('pngload')
    expect(image.width).to be_between(1, 250)
    expect(attachment.thumb_url).to be_present
  end
end
