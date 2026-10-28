# frozen_string_literal: true

# Tolzar: the production domain is fronted by CyberPanel / OpenLiteSpeed with
# LiteSpeed Cache (LSCache) enabled. LSCache was caching AUTHENTICATED, dynamic
# API responses and the SPA shell HTML (observed: `x-litespeed-cache: hit` on
# `/api/v1/accounts/:id/agents` and `/`), despite `Cache-Control: private`.
#
# Effects of that misconfiguration:
#   * Stale data — a newly added agent / reassigned conversation keeps showing
#     the old list on the canonical URL until the proxy cache expires.
#   * Data-isolation risk — a `private` per-user response can be cached and
#     served to another request.
#
# LSCache honours the `X-LiteSpeed-Cache-Control: no-cache` response tag, so we
# emit it (and harden the standard Cache-Control) for DYNAMIC responses only.
# Static, fingerprinted assets (JS/CSS/images/fonts under /vite, /packs,
# /assets, ActiveStorage) stay cacheable for performance. This fix is portable:
# it protects the product behind any LSCache/CDN layer a customer deploys to.
class TolzarNoProxyCache
  STATIC_PATH = %r{\A/(vite|vite-dev|packs|assets|rails/active_storage|favicon|brand-assets|widget|packs-test)}.freeze
  # /api/v1/accounts/<id>/tolzar/... and /tolzar/... (mirror, Meta, MCP doors).
  TOLZAR_PATH = %r{\A(?:/api/v1/accounts/[^/]+)?/tolzar(?:/|\z|\.)}
  STATIC_EXT = /\.(?:js|mjs|css|map|png|jpe?g|gif|svg|webp|avif|ico|woff2?|ttf|eot|wasm|mp3|mp4|webm|pdf)\z/i.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    path = env['PATH_INFO'].to_s

    # NOTE: a request-header-triggered LSCache purge (`X-Tolzar-Purge`) was
    # removed — it let any unauthenticated client flush the entire proxy cache.
    # A one-off purge is now done out-of-band (CyberPanel) at deploy time only.

    if path.match?(TOLZAR_PATH)
      # H1 (full-sec): every Tolzar response (the workspace export is application/gzip, not JSON)
      # is per-user data; never stored by a proxy, whatever its content type.
      headers['X-LiteSpeed-Cache-Control'] = 'no-cache'
      headers['Cache-Control'] = 'no-store, private'
    elsif !(path.match?(STATIC_PATH) || path.match?(STATIC_EXT))
      content_type = (headers['Content-Type'] || headers['content-type']).to_s
      if content_type.include?('text/html') || content_type.include?('application/json')
        headers['X-LiteSpeed-Cache-Control'] = 'no-cache'
        headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0, private'
      end
    end

    [status, headers, body]
  end
end

Rails.application.config.middleware.use TolzarNoProxyCache
