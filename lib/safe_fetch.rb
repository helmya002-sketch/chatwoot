require 'ssrf_filter'

module SafeFetch
  DEFAULT_ALLOWED_CONTENT_TYPE_PREFIXES = %w[image/ video/].freeze
  DEFAULT_ALLOWED_CONTENT_TYPES = [].freeze
  DEFAULT_SENSITIVE_HEADERS = %w[authorization cookie proxy-authorization].freeze
  DEFAULT_OPEN_TIMEOUT = 2
  DEFAULT_READ_TIMEOUT = 20
  DEFAULT_MAX_BYTES_FALLBACK_MB = 40

  Result = Data.define(:tempfile, :filename, :content_type) do
    def original_filename
      filename
    end
  end

  class Error < StandardError; end
  class InvalidUrlError < Error; end
  class UnsafeUrlError < Error; end
  class FetchError < Error; end
  class HttpError < Error; end
  class FileTooLargeError < Error; end
  class UnsupportedContentTypeError < Error; end
  class UnsupportedMethodError < Error; end

  def self.fetch(url, **, &)
    raise ArgumentError, 'block required' unless block_given?

    SafeFetch::Fetcher.new(SafeFetch::RequestOptions.new(url: url, **)).fetch(&)
  rescue SsrfFilter::InvalidUriScheme, URI::InvalidURIError => e
    raise InvalidUrlError, e.message
  rescue SsrfFilter::Error, Resolv::ResolvError => e
    raise UnsafeUrlError, e.message
  end

  def self.allow_private_network?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('SAFE_FETCH_ALLOW_PRIVATE_NETWORK', false))
  end

  # Tolzar: a narrow alternative to SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true (which opens the private network
  # to every tenant's webhooks). SAFE_FETCH_ALLOWED_PRIVATE_HOSTS is a comma-separated list of host names
  # (or IP literals) whose resolved private addresses may be fetched; every other private destination
  # stays blocked. Unset, it defaults to the host of TOLZAR_BRAIN_URL (the same default as
  # Tolzar::BrainClient), so the Tolzar agent bot reaches the brain on the private Docker network.
  # Set it to an empty string to allow none.
  def self.allowed_private_hosts
    raw = ENV.fetch('SAFE_FETCH_ALLOWED_PRIVATE_HOSTS') { default_allowed_private_host.to_s }
    raw.split(',').map { |host| host.strip.downcase }.reject(&:empty?)
  end

  def self.allowed_private_host?(hostname)
    hostname.present? && allowed_private_hosts.include?(hostname.to_s.downcase)
  end

  def self.default_allowed_private_host
    URI.parse(ENV.fetch('TOLZAR_BRAIN_URL', 'http://tolzar-brain:8080')).host
  rescue URI::InvalidURIError
    nil
  end
end
