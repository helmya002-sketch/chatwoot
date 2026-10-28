# Proves that avatar and attachment thumbnails (ActiveStorage variants through libvips) work in this image.
# The image's libvips is built from source without GPL libraries (see docker/Dockerfile); this catches a
# missing loader/saver or shared library before customers do.
#   Production container (Server ops): bundle exec rails tolzar:verify_image_variants
#   Spec: spec/tolzar/image_variants_spec.rb
module Tolzar::ImageVariantCheck
  # What Avatarable#avatar_url and Attachment#thumb_url request.
  THUMBNAIL = { resize_to_fill: [250, nil] }.freeze
  # The well-known 1x1 GIF: this libvips can read GIF but has no GIF saver.
  GIF_1PX = Base64.decode64('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7')
  WEB_FORMATS = { 'image/png' => 'png', 'image/jpeg' => 'jpg' }.freeze
  EXPECTED_LOADER = { 'png' => 'pngload', 'jpg' => 'jpegload' }.freeze

  module_function

  def samples
    picture = (Vips::Image.black(320, 200) + [40, 120, 200]).cast(:uchar)
    {
      'image/png' => picture.write_to_buffer('.png'),
      'image/jpeg' => picture.write_to_buffer('.jpg', Q: 85),
      'image/gif' => GIF_1PX
    }
  end

  # Same output format rule as ActiveStorage::Variant: web image types keep their format, the rest become PNG.
  def variant_format(content_type)
    ActiveStorage.web_image_content_types.include?(content_type) ? WEB_FORMATS.fetch(content_type) : 'png'
  end

  # Runs every sample through the configured variant transformer; returns one line per sample, raises on failure.
  def run!
    require 'vips' # loaded on use, as ImageProcessing does, so app boot never loads libvips
    samples.map do |content_type, bytes|
      format = variant_format(content_type)
      output = transform(bytes, format)
      loader = output.get('vips-loader')
      raise "#{content_type}: thumbnail is #{loader}, expected #{format}" unless loader.start_with?(EXPECTED_LOADER.fetch(format))
      raise "#{content_type}: thumbnail is #{output.width}px wide" unless output.width.between?(1, 250)

      "#{content_type} -> #{format} #{output.width}x#{output.height} ok"
    end
  end

  def transform(bytes, format)
    Tempfile.create(['tolzar-variant-check', '.img'], binmode: true) do |source|
      source.write(bytes)
      source.rewind
      ActiveStorage::Variation.wrap(THUMBNAIL.merge(format: format)).transform(source) do |output|
        return Vips::Image.new_from_buffer(output.read, '')
      end
    end
  end
end
