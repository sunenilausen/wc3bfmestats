Rails.application.routes.draw do
  resources :lobbies, except: [ :destroy ] do
    member do
      post :balance
      post :copy
    end
  end
  resources :wc3stats_replays
  resources :appearances, only: [ :index, :show ]
  resources :matches do
    collection do
      post :sync
    end
    member do
      post :refetch
      post :toggle_reviewed
    end
  end
  resources :factions, except: [ :new, :create, :destroy ]
  resources :players, constraints: { id: /[^\/]+/ } do
    resource :relationships, only: [ :show ], controller: "player_relationships"
    member do
      get :match_history
    end
  end

  namespace :admin do
    root to: "dashboard#index"
    resources :players, only: [], constraints: { id: /[^\/]+/ } do
      resource :merge, only: %i[new create], controller: "player_merges"
    end
    get "analytics", to: "analytics#index", as: :analytics
    get "suspicious_matches", to: "suspicious_matches#index", as: :suspicious_matches
  end

  devise_for :users
  post "dev_sign_in", to: "dev_sessions#create", as: :dev_sign_in if Rails.env.development? || Rails.env.test?
  get "home/index"
  get "statistics", to: "home#statistics", as: :statistics
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  root to: "home#index"
end
