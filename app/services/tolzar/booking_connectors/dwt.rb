# Tolzar booking connector, DWT Bookings adapter (its token API: one endpoint, `?r=<resource>`, bearer token with
# read and/or write scope). Read: catalog, schedule, bookings, customers. Write: upsert a customer, create a DRAFT
# booking (staff confirm it in DWT's app). The adapter interface every booking system implements:
#   catalog, schedule(from:, to:), bookings(phone:, conversation_id:), customers(phone:, email:),
#   upsert_customer(attrs), create_draft(body)
class Tolzar::BookingConnectors::Dwt
  TIMEOUT = 10
  MAX_BYTES = 2.megabytes

  def initialize(base_url:, token:)
    @base_url = base_url
    @token = token
  end

  def catalog
    data = get('catalog')
    Array(data['items'] || data['courses'] || data['catalog'])
  end

  def schedule(from:, to:)
    get('schedule', from: from.to_s, to: to.to_s)
  end

  def bookings(phone: nil, conversation_id: nil)
    Array(get('bookings', { phone: phone, tolzar_conversation_id: conversation_id }.compact)['bookings'])
  end

  def customers(phone: nil, email: nil)
    Array(get('customers', { phone: phone, email: email }.compact)['customers'])
  end

  def upsert_customer(attrs)
    post('customer', attrs)
  end

  def create_draft(body)
    post('booking', body)
  end

  private

  def get(resource, query = {})
    request(:get, url(resource, query))
  end

  def post(resource, body)
    request(:post, url(resource), body.to_json)
  end

  def url(resource, query = {})
    uri = URI(@base_url)
    params = URI.decode_www_form(uri.query.to_s) + [['r', resource]] + query.map { |k, v| [k.to_s, v.to_s] }
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  def request(method, url, body = nil)
    data = nil
    SafeFetch.fetch(url, method: method, body: body, max_bytes: MAX_BYTES, open_timeout: TIMEOUT, read_timeout: TIMEOUT,
                         headers: { 'Authorization' => "Bearer #{@token}", 'Accept' => 'application/json',
                                    'Content-Type' => 'application/json' },
                         sensitive_headers: ['Authorization'], validate_content_type: false) do |result|
      data = JSON.parse(result.tempfile.read)
    end
    data.is_a?(Hash) ? data : { 'items' => data } # a bare list (the catalog) as items
  rescue SafeFetch::HttpError => e
    raise "DWT Bookings refused the call (#{e.message.to_s.first(40)})"
  rescue SafeFetch::Error => e
    raise "DWT Bookings could not be reached (#{e.class.name.demodulize})"
  rescue JSON::ParserError
    raise 'DWT Bookings answered with something that is not JSON'
  end
end
