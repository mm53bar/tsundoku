require "zip"
require "nokogiri"

# Extracts metadata from an EPUB file's internal OPF (Open Packaging
# Format) document. Returns a hash with whatever Dublin Core fields the
# OPF exposes; missing fields are nil/empty. Never raises on a malformed
# EPUB — returns nil instead so callers can decide how to handle it
# (typically: log + move to a "needs review" subdir).
#
# EPUB structure:
#   META-INF/container.xml      ← points at the package OPF
#   <something>.opf             ← Dublin Core metadata + manifest + spine
class EpubParser
  Result = Struct.new(
    :title, :subtitle, :authors, :identifiers, :publisher, :pubdate,
    :description, :language, :series, :series_index,
    keyword_init: true
  )

  ISBN_DIGITS = /\A[\dXx]{10}(?:\d{3})?\z/

  def self.parse(file_path)
    new(file_path).parse
  end

  def initialize(file_path)
    @file_path = file_path
  end

  def parse
    Zip::File.open(@file_path) do |zip|
      opf_doc = locate_opf(zip)
      return nil unless opf_doc

      metadata = opf_doc.at_xpath("//metadata")
      return nil unless metadata

      Result.new(
        title: text_at(metadata, "title"),
        subtitle: nil,
        authors: authors_from(metadata),
        identifiers: identifiers_from(metadata),
        publisher: text_at(metadata, "publisher"),
        pubdate: parse_date(text_at(metadata, "date")),
        description: text_at(metadata, "description"),
        language: text_at(metadata, "language"),
        series: calibre_meta(metadata, "calibre:series"),
        series_index: calibre_meta(metadata, "calibre:series_index")
      )
    end
  rescue Zip::Error, Errno::ENOENT, Errno::EACCES, Nokogiri::XML::SyntaxError => e
    Rails.logger.warn("EpubParser: #{e.class} parsing #{@file_path}: #{e.message}")
    nil
  end

  private

  def locate_opf(zip)
    container = zip.find_entry("META-INF/container.xml")
    return nil unless container

    container_doc = Nokogiri::XML(container.get_input_stream.read).tap(&:remove_namespaces!)
    opf_path = container_doc.at_xpath("//rootfile/@full-path")&.value
    return nil unless opf_path.present?

    opf_entry = zip.find_entry(opf_path)
    return nil unless opf_entry

    Nokogiri::XML(opf_entry.get_input_stream.read).tap(&:remove_namespaces!)
  end

  def text_at(metadata, name)
    el = metadata.at_xpath(name)
    return nil unless el
    text = el.text.to_s.strip
    text.empty? ? nil : text
  end

  # Creators are dc:creator with role=aut by convention. Some EPUBs omit
  # the role and just list creators as authors; treat anything without an
  # explicit non-author role as an author.
  def authors_from(metadata)
    metadata.xpath("creator").map do |el|
      role = el["role"] || el["opf:role"]
      next nil if role.present? && role != "aut"
      name = el.text.to_s.strip
      name.empty? ? nil : name
    end.compact
  end

  # Returns array of { kind:, value: } hashes ready for book_identifiers.
  # ISBN inference: if scheme is missing but the value looks like an ISBN
  # by digit pattern, classify it as isbn13 or isbn10 based on length.
  def identifiers_from(metadata)
    metadata.xpath("identifier").map do |el|
      raw_value  = el.text.to_s.strip
      next nil if raw_value.empty?

      scheme = (el["scheme"] || el["opf:scheme"]).to_s.downcase.strip
      kind = classify_identifier(scheme, raw_value)
      value = scheme.start_with?("isbn") || kind.start_with?("isbn") ? raw_value.gsub(/[^\dXx]/, "") : raw_value
      { kind: kind, value: value }
    end.compact
  end

  def classify_identifier(scheme, value)
    return scheme if %w[isbn isbn10 isbn13 asin doi].include?(scheme)
    return "isbn" if scheme.start_with?("isbn")
    return "asin" if scheme == "amazon"
    return "uuid" if scheme == "uuid" || value.match?(/\A[0-9a-f]{8}-/i)

    digits = value.gsub(/[^\dXx]/, "")
    return "isbn13" if digits.length == 13 && digits.match?(ISBN_DIGITS)
    return "isbn10" if digits.length == 10 && digits.match?(ISBN_DIGITS)

    scheme.presence || "other"
  end

  def parse_date(text)
    return nil if text.blank?
    Date.parse(text)
  rescue ArgumentError, TypeError
    nil
  end

  # Calibre stores series info as non-Dublin-Core <meta name="calibre:series"
  # content="..."/> elements in the same metadata block. Read them when
  # available so we don't lose series data on ingest.
  def calibre_meta(metadata, name)
    el = metadata.at_xpath("meta[@name='#{name}']")
    return nil unless el
    content = el["content"].to_s.strip
    content.empty? ? nil : content
  end
end
