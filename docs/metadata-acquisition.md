# Book metadata acquisition

Empirical research notes for the Phase 2 ingest pipeline. The patterns below are based on a real metadata-enrichment session against the live library, not theoretical API docs — quirks listed are quirks that actually bit.

The two real challenges are:

1. **Identity resolution** — matching a book in our library to the right record in a source.
2. **Source reliability** — every free metadata source has a quirk that bites under volume.

Bias toward **no match over a wrong match** everywhere.

## Source ranking

| Source | Use | Reliability | Notes |
|---|---|---|---|
| **Hardcover** | Primary | High from homelab IP | GraphQL. Description, ISBNs, release dates, ratings, genres, covers. ~80% match rate. Workhorse. |
| **Wikidata** | Awards & curated lists | High but slow | Only structured source for "won the Pulitzer" / "on Oprah's list." SPARQL. Fuzzier matching. |
| **Curated lists you seed** | Lists you control | Total | Not an API — store the list once (e.g. greatest-books top-N), match locally. |
| **Open Library** | Fallback only | Spotty | 403s `node`/`undici` while still answering `curl` (fingerprinting). Use Faraday with a real UA, pace it hard. |
| **Google Books** | **Avoid** | Bad | HTTP 429 from homelab IPs almost immediately, even unauthenticated. Don't bother. |

## Hardcover (the core recipe)

**Endpoint and auth:**

```
POST https://api.hardcover.app/v1/graphql
Header:  authorization: Bearer <JWT>
```

Store the raw JWT (no `Bearer ` prefix); prepend `Bearer ` in code. Token from Settings → API is ~900 chars, valid one year — long values truncate on paste, so load it from a file or env var, not a pasted shell arg.

**The query that works:**

```graphql
query Match($t: String!) {
  books(where: {title: {_eq: $t}}, order_by: {users_count: desc}, limit: 5) {
    id
    title
    description
    release_date
    rating
    contributions { author { name } }
    editions(where: {isbn_13: {_is_null: false}}, limit: 1) { isbn_13 }
    image { url }
  }
}
```

**Critical quirks:**

- `_ilike` is blocked server-side (HTTP 403). You must use `_eq`. That means you **cannot fuzzy-match** — feed it a clean exact title.
- Normalize the title before querying: strip everything from the first `:` or `(`. This turns "Project Hail Mary: A Novel" → "Project Hail Mary" and "A Tale of Two Cities (Barnes & Noble Classics Series)" → "A Tale of Two Cities" — the canonical titles Hardcover actually stores.
- `order_by: {users_count: desc}` returns the most-popular (canonical) edition first.
- Always verify the author before accepting a match — multiple books share a title. Match on surname-token overlap.
- On no confident match, leave the gap. Guessing is worse than empty.

**Ruby client sketch:**

```ruby
class HardcoverClient
  ENDPOINT = "https://api.hardcover.app/v1/graphql"

  def initialize(token: ENV.fetch("HARDCOVER_APP_API_TOKEN"))
    @auth = token.start_with?("Bearer") ? token : "Bearer #{token}"
  end

  # returns a Hash of metadata or nil
  def lookup(title:, author:)
    clean = clean_title(title)
    books = query(clean)
    pick  = books.find { |b| author_match?(author, b) } ||
            (books.one? ? books.first : nil)
    return nil unless pick

    {
      hardcover_id: pick["id"],
      title:        pick["title"],
      description:  pick["description"],
      isbn13:       pick.dig("editions", 0, "isbn_13"),
      release_date: pick["release_date"],
      rating:       pick["rating"],
      cover_url:    pick.dig("image", "url"),
    }
  end

  private

  def query(title)
    body = { query: GQL, variables: { t: title } }
    resp = Faraday.post(ENDPOINT, body.to_json,
             "content-type" => "application/json", "authorization" => @auth)
    JSON.parse(resp.body).dig("data", "books") || []
  end

  def clean_title(t) = t.split(/[:(]/).first.to_s.strip

  def author_match?(lib_author, book)
    want = surname_tokens(lib_author)
    book["contributions"].to_a.any? do |c|
      (surname_tokens(c.dig("author", "name")) & want).any?
    end
  end

  def surname_tokens(name)
    name.to_s.downcase.unicode_normalize(:nfd).gsub(/[^a-z0-9 ]/, " ")
        .split.select { |w| w.length > 2 }.to_set
  end

  GQL = <<~G
    query Match($t: String!) {
      books(where: {title: {_eq: $t}}, order_by: {users_count: desc}, limit: 5) {
        id title description release_date rating
        contributions { author { name } }
        editions(where: {isbn_13: {_is_null: false}}, limit: 1) { isbn_13 }
        image { url }
      }
    }
  G
end
```

## Identity resolution

Every source needs the right record. The matching that worked:

```ruby
def norm(s)
  s.to_s.downcase.unicode_normalize(:nfd)
   .split(/[:(]/).first.to_s          # drop subtitle
   .gsub("&", " and ")
   .gsub(/[^a-z0-9 ]/, " ")
   .sub(/\A(the|a|an) /, "")
   .squish
end

# a few numeral/spelling aliases bite — handle them explicitly
ALIASES = { "1984" => "nineteen eighty four" }
```

Rules of thumb:

- **ISBN-first when you have one** — most precise; skips title ambiguity entirely. Hardcover: `editions(where: {isbn_13: {_eq: $isbn}})`.
- Otherwise normalized-title `_eq` + author-surname overlap.
- Treat a title-only match as valid only if the title is distinctive (long / multi-word). For short common titles (*Emma*, *Home*, *Jack*) **require** the author match or you'll grab the wrong book.
- Bias toward no match over a wrong match.

## Awards & curated-list membership (Wikidata)

This is the only place to get "won the Pulitzer" / "on Oprah's list" as structured data. Two-step: fuzzy-find the work entity, then read its *award received* (P166) — which Wikidata also uses for list memberships.

```ruby
# 1 req/sec, descriptive User-Agent, accept application/sparql-results+json
SPARQL = <<~Q
  SELECT ?work ?workLabel ?award ?awardLabel ?year WHERE {
    SERVICE wikibase:mwapi {
      bd:serviceParam wikibase:api "EntitySearch" ;
                      wikibase:endpoint "www.wikidata.org" ;
                      mwapi:search "%<title>s" ;
                      mwapi:language "en" .
      ?work wikibase:apiOutputItem mwapi:item .
    }
    ?work wdt:P50 ?a .
    ?a rdfs:label ?al . FILTER(LANG(?al)="en" && CONTAINS(LCASE(?al), "%<surname>s"))
    OPTIONAL { ?work wdt:P166 ?award .
               OPTIONAL { ?work p:P166 [ ps:P166 ?award; pq:P585 ?year ] } }
    SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
  } LIMIT 100
Q
```

Handling notes:

- A work returns many entities (one per edition/translation). Group by `?work` and pick the one with the most awards — that's the canonical work.
- Wikidata files both prizes and lists under P166. You decide award-vs-list with a lookup table you maintain — e.g. *Pulitzer Prize for Fiction*, *Hugo Award for Best Novel* → award; *Oprah's Book Club*, *NPR Top 100 Science Fiction and Fantasy Books*, *Modern Library 100 Best Novels* → list.
- Skip kid/YA prizes (Newbery/Caldecott/Printz) if not relevant; skip QID-labeled junk (labels like `Q137449821` that didn't resolve to English).
- ~3–4% of a general library has a major award, so most lookups return nothing — that's normal, not a failure.

## Curated lists you control

These aren't APIs — seed the list once (title + author per entry) and match locally with the same `norm` + surname logic. This is how you get `list:greatest-books` / `list:oprah` membership without depending on anyone's uptime. Also catches genre/popular titles the literary-canon sources miss.

## Audience (adult / YA / middle-grade / picture-book)

**Be warned:** deriving audience from an LLM over scraped subjects was the **least reliable** thing attempted in research — it mis-classified obvious cases (Gaiman's *Stardust* as juvenile, etc.). For acquisition, prefer signals you can trust:

- Hardcover genres/taggings on the matched book.
- Failing that, a small deterministic heuristic, and **mark low-confidence ones for human review** rather than auto-committing.

## Orchestration shape

Keep acquisition behind one service that returns a plain result; the app stores it however it likes:

```ruby
class BookMetadataFetcher
  def call(title:, author:, isbn: nil)
    hc    = HardcoverClient.new.lookup(title:, author:)         # desc, isbn, date, cover
    wd    = WikidataAwards.new.lookup(title:, author:)          # awards[], lists[]
    canon = CanonListMatcher.match(title:, author:)             # your seeded lists
    {
      description:  hc&.dig(:description),
      isbn13:       isbn || hc&.dig(:isbn13),
      release_date: hc&.dig(:release_date),
      cover_url:    hc&.dig(:cover_url),
      awards:       wd[:awards],
      lists:        (wd[:lists] + canon).uniq,
      source_confidence: hc ? :matched : :unmatched,
    }
  end
end
```

## Rate-limit reality

Do this **one book at a time as books arrive**, not in bulk. Single-book-on-ingest stays under every limit effortlessly — bulk runs are what triggered the Google Books 429 and Open Library 403s. Hardcover is friendly but still pace it (~250ms). Cache by `hardcover_id` / ISBN so re-runs don't re-fetch.
