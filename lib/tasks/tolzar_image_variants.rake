namespace :tolzar do
  desc 'Check that avatar and attachment thumbnails (ActiveStorage variants through libvips) work in this image'
  task verify_image_variants: :environment do
    require 'vips'
    puts "libvips #{Vips.version_string}, variant processor #{ActiveStorage.variant_processor}"
    Tolzar::ImageVariantCheck.run!.each { |line| puts line }
    puts 'tolzar:verify_image_variants OK'
  end
end
