# Tolzar licence compliance: the image's libvips is built without libimagequant (GPL-3.0), so it has no GIF
# saver (GIF save needs a quantiser). Rails keeps a variant in the source format only for web image types, so
# GIF is left out: avatar and attachment thumbnails of a GIF are PNG (first frame, as before; thumbnails were
# never animated). PNG and JPEG keep their own format.
Rails.application.config.active_storage.web_image_content_types = %w[image/png image/jpeg]
