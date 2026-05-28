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

  resources :shelves, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]

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
  # by mnemonic handle in the URL (see Kobo::BaseController).
  scope "/kobo/:handle", module: "kobo", as: :kobo do
    get "/", to: "base#root"
  end

  root "library#index"
end
