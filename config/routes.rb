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

  root "library#index"
end
