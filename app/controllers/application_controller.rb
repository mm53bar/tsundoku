class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_authentication
  helper_method :current_user, :signed_in?

  # NOTE: "Remote-User" maps to the CGI-standard REMOTE_USER env var, which
  # ActionDispatch::Http::Headers reads UNPREFIXED — so request.headers["Remote-User"]
  # returns nil even when the HTTP header is present. We access these via the
  # HTTP_-prefixed env keys directly so all four work consistently.
  PROXY_USERNAME_HEADER = "HTTP_REMOTE_USER".freeze
  PROXY_EMAIL_HEADER    = "HTTP_REMOTE_EMAIL".freeze
  PROXY_NAME_HEADER     = "HTTP_REMOTE_NAME".freeze

  private

  def current_user
    @current_user ||= resolve_current_user
  end

  def signed_in?
    current_user.present?
  end

  def require_authentication
    return if signed_in?

    if Rails.env.development?
      redirect_to dev_login_path
    else
      render plain: "Authentication required. This app must be reached via the upstream Authelia-protected proxy.",
             status: :unauthorized
    end
  end

  def resolve_current_user
    if Rails.env.development? && session[:dev_user_id].present?
      return User.find_by(id: session[:dev_user_id])
    end

    username = request.headers[PROXY_USERNAME_HEADER].presence
    return nil unless username

    User.find_or_provision_from_proxy(
      username: username,
      email:    request.headers[PROXY_EMAIL_HEADER].presence,
      name:     request.headers[PROXY_NAME_HEADER].presence,
    )
  end

  # Per-page preload for the book-card shelf quick-add (the "+" button
  # in the top-right of each cover). Returns [user_shelves,
  # shelf_member_ids_by_book] — caller fans these out to render
  # "books/card" without N+1 lookups inside the picker_panel. Anonymous
  # users get empty fallbacks so the card just renders without the +.
  def preload_shelf_membership_for(books)
    return [ [], Hash.new(Set.new) ] unless current_user

    shelves = current_user.shelves.by_name.to_a
    memberships = ShelfEntry.joins(:shelf)
                            .where(book_id: books.map(&:id), shelves: { user_id: current_user.id })
                            .pluck(:book_id, :shelf_id)
    member_ids_by_book = memberships.group_by(&:first).transform_values { |pairs| pairs.map(&:last).to_set }
    member_ids_by_book.default = Set.new
    [ shelves, member_ids_by_book ]
  end
end
