Rails.application.routes.draw do
  delete "/sign_out", to: "sessions#destroy", as: :sign_out

  if Rails.env.development?
    get  "/dev_login", to: "dev_sessions#new",    as: :dev_login
    post "/dev_login", to: "dev_sessions#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check

  post "/library/import", to: "library#import", as: :library_import

  resources :books, only: [ :show, :edit, :update ] do
    member do
      get  :cover
      get  :download
      post :enrich
      # Toggle a book's membership in one of the current user's shelves.
      # Single endpoint that creates the ShelfEntry if missing or destroys
      # it if present — symmetric with the way the UI's checkbox works.
      post "shelves/:shelf_id/toggle", to: "shelf_entries#toggle", as: :toggle_shelf
    end
    resource :reading, only: [ :update ]
  end

  resources :authors, only: [ :index, :show ] do
    member do
      get :more_books
    end
  end

  resources :series, only: [ :index, :show ] do
    member do
      get :more_books
    end
  end

  resources :shelves, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    member do
      delete "books/:book_id", to: "shelves#remove_book", as: :remove_book
    end
  end

  resources :lists, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    member do
      get  :reimport
      post :reimport
    end
    resources :list_entries, only: [ :create, :destroy ], path: "entries"
  end

  get  "/ingest",      to: "ingest#index", as: :ingest_index
  post "/ingest/scan", to: "ingest#scan",  as: :ingest_scan

  # User-facing "Sync with Kobo" settings page. Authelia-protected as normal.
  get  "/kobo-sync",            to: "kobo_sync#show",       as: :kobo_sync
  post "/kobo-sync/regenerate", to: "kobo_sync#regenerate", as: :regenerate_kobo_sync

  # Kobo device endpoints. Authelia bypass is configured at NPM; auth is
  # by mnemonic handle in the URL (see Kobo::BaseController). Anything we
  # don't implement yet falls through to the catch-all and returns {}.
  scope "/kobo/:handle", module: "kobo", as: :kobo do
    get "/", to: "base#root"

    # Initialization — tells the device where to find every other
    # endpoint. Must be served (not fall through to {} fallback)
    # or newer firmware fails the sync.
    get "v1/initialization", to: "initialization#show", as: :initialization

    # Phase B: library sync, cover serving, EPUB download.
    get "v1/library/sync", to: "sync#sync", as: :library_sync

    get "v1/library/:book_uuid/metadata",
        to:          "sync#metadata",
        as:          :book_metadata,
        constraints: { book_uuid: /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/ }

    # NB: greyscale segment is intentionally permissive — the device
    # substitutes its own representation ("False" with a capital F from
    # the {IsGreyscale} template variable, not "false" as in the literal
    # template). Anchoring on a strict regex caused covers to fall
    # through to the {} fallback and books to render without art.
    get ":book_uuid/:width/:height/:greyscale/image.jpg",
        to:          "covers#show",
        as:          :cover,
        constraints: {
          book_uuid: /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/,
          width:     /\d+/,
          height:    /\d+/,
          greyscale: /[A-Za-z01]+/
        }

    get "download/:book_id/:format",
        to:          "downloads#show",
        as:          :download,
        constraints: { book_id: /\d+/, format: /EPUB3?|KEPUB/ }

    # Catch-all — MUST stay last.
    match "*path", to: "base#fallback", via: :all
  end

  root "library#index"
end
