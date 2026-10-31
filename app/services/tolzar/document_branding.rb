# Tolzar booking documents: a workspace's template settings (owner), kept in account.settings
# 'tolzar_document_branding' = { colour, address, logo, titles: {type => text}, terms: {type => text} }.
#   colour  #RRGGBB, the accent (a rule and the headings)
#   logo    a data:image/png|jpeg;base64 URI of at most LOGO_MAX bytes: the renderer has no network, so a logo is
#           never fetched from a URL
#   titles  the document title per type (default: the type's name); terms the "Good to know" text per type
#           (default: Tolzar::DocumentPacks::DEFAULT_TERMS)
# clean returns [settings, errors]; nothing is saved when there is an error.
class Tolzar::DocumentBranding
  KEY = 'tolzar_document_branding'
  COLOUR = /\A#[0-9A-Fa-f]{6}\z/
  LOGO = %r{\Adata:image/(png|jpeg);base64,[A-Za-z0-9+/=]+\z}
  LOGO_MAX = 90_000
  TITLE_MAX = 60
  TERMS_MAX = 2000
  ADDRESS_MAX = 300

  def self.read(account)
    stored = (account.settings || {})[KEY]
    stored.is_a?(Hash) ? stored : {}
  end

  def self.clean(given)
    given = given.to_unsafe_h if given.respond_to?(:to_unsafe_h)
    given = given.is_a?(Hash) ? given.deep_stringify_keys : {}
    errors = []
    out = { 'colour' => colour(given['colour'], errors), 'address' => address(given['address'], errors),
            'logo' => logo(given['logo'], errors) }
    out['titles'] = per_type(given['titles'], TITLE_MAX, 'titles', errors)
    out['terms'] = per_type(given['terms'], TERMS_MAX, 'terms', errors)
    [out.compact, errors]
  end

  # What the printable page and the PDF renderer get for one document type.
  def self.for_render(account, doc_type)
    b = read(account)
    { name: account.name, address: b['address'], colour: b['colour'], logo: b['logo'],
      title: (b['titles'] || {})[doc_type].presence,
      terms: (b['terms'] || {})[doc_type].presence || Tolzar::DocumentPacks.default_terms(doc_type).presence }.compact
  end

  def self.colour(value, errors)
    value = value.to_s.strip
    return value.presence if value.empty? || value.match?(COLOUR)

    errors << 'colour: #RRGGBB'
    nil
  end

  def self.address(value, errors)
    value = value.to_s.strip
    return value.presence if value.length <= ADDRESS_MAX

    errors << "address: at most #{ADDRESS_MAX} characters"
    nil
  end

  def self.logo(value, errors)
    value = value.to_s.strip
    return value.presence if value.empty? || (value.match?(LOGO) && value.bytesize <= LOGO_MAX)

    errors << "logo: a PNG or JPEG of at most #{LOGO_MAX / 1000} KB"
    nil
  end

  def self.per_type(value, max, name, errors)
    value = value.is_a?(Hash) ? value : {}
    Tolzar::DocumentSpec::TYPES.each_with_object({}) do |type, out|
      text = value[type].to_s.strip
      next if text.empty?

      if text.length <= max
        out[type] = text
      else
        errors << "#{name}.#{type}: at most #{max} characters"
      end
    end
  end

  private_class_method :colour, :address, :logo, :per_type
end
