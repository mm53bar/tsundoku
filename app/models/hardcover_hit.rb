# One book from Hardcover's Typesense search, reduced to the fields lists
# care about. Also round-trips through the small hash stored in
# ListEntry#resolution_candidates.
class HardcoverHit
  attr_reader :id, :title, :author_names, :release_year, :cover_url, :users_count, :alternative_titles

  def self.from_document(doc)
    image = doc["image"].is_a?(Hash) ? doc["image"] : {}
    new(
      id: doc["id"].to_i,
      title: doc["title"].to_s,
      author_names: author_names_from(doc),
      release_year: doc["release_year"],
      cover_url: image["url"].presence,
      users_count: doc["users_count"].to_i,
      alternative_titles: Array(doc["alternative_titles"]),
      compilation: doc["compilation"] == true
    )
  end

  # `author_names` also lists foreword writers, illustrators and cover
  # artists; keep the credited authors when Hardcover says who they are.
  def self.author_names_from(doc)
    authors = Array(doc["contributions"])
      .select { |c| c.is_a?(Hash) && c["contribution"].in?([ nil, "Author" ]) }
      .filter_map { |c| c.dig("author", "name") }
    authors.presence || Array(doc["author_names"])
  end

  def self.from_candidate(hash)
    hash = hash.to_h.stringify_keys
    new(
      id: hash["id"].to_i,
      title: hash["title"].to_s,
      author_names: Array(hash["author_names"]),
      release_year: hash["release_year"],
      cover_url: hash["cover_url"],
      users_count: hash["users_count"].to_i
    )
  end

  def initialize(id:, title:, author_names: [], release_year: nil, cover_url: nil, users_count: 0, alternative_titles: [], compilation: false)
    @id = id
    @title = title
    @author_names = author_names
    @release_year = release_year
    @cover_url = cover_url
    @users_count = users_count
    @alternative_titles = alternative_titles
    @compilation = compilation
  end

  def compilation?
    @compilation
  end

  def author
    author_names.join(", ").presence
  end

  def to_candidate
    {
      "id" => id,
      "title" => title,
      "author_names" => author_names,
      "release_year" => release_year,
      "cover_url" => cover_url,
      "users_count" => users_count
    }
  end
end
