module ShelfmarkHelper
  # Build a Shelfmark search URL pre-filled with the given fields. Returns
  # nil when SHELFMARK_URL is unset or no title is supplied — call sites
  # should guard on that so the link is hidden when the integration isn't
  # configured.
  #
  # Shelfmark's frontend bootstraps a search from URL query params on
  # mount (see calibrain/shelfmark
  # src/frontend/src/utils/parseUrlSearchParams.ts).
  def shelfmark_search_url(title:, author: nil, isbn: nil)
    base = Rails.configuration.x.shelfmark_url
    return nil if base.blank? || title.blank?

    params = { title: title, content_type: "ebook" }
    params[:author] = author if author.present?
    params[:isbn]   = isbn   if isbn.present?

    "#{base.sub(%r{/\z}, '')}/?#{params.to_query}"
  end
end
