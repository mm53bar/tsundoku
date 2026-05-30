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

  # Render a "Find via Shelfmark" link if the helper can build a URL.
  # Yields a block for caller-controlled markup; the block receives no
  # args. Returns nil when no URL is available so the caller can omit
  # surrounding markup with a simple `if`.
  def shelfmark_link_to(title:, author: nil, isbn: nil, **link_options, &block)
    url = shelfmark_search_url(title: title, author: author, isbn: isbn)
    return nil unless url
    link_to(url, target: "_blank", rel: "noopener", **link_options, &block)
  end
end
