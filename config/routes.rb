Rails.application.routes.draw do
  delete "/sign_out", to: "sessions#destroy", as: :sign_out

  if Rails.env.development?
    get  "/dev_login", to: "dev_sessions#new",    as: :dev_login
    post "/dev_login", to: "dev_sessions#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check

  post "/library/import", to: "library#import", as: :library_import

  resources :books, only: [ :show ] do
    member do
      get :cover
    end
  end

  root "library#index"
end
