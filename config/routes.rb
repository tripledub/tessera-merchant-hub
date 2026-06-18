Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "rails/health#show"

  # Authenticated users land on applicants; everyone else goes to sign-in.
  authenticated :user do
    root to: "applicants#index", as: :authenticated_root
  end
  root to: redirect("/users/sign_in")

  resources :merchants, only: %i[new create index show edit update]

  resources :applicants, only: %i[new create index show edit update] do
    resources :kyc_principals, only: %i[new create edit update destroy], shallow: true
    resources :kyc_documents,  only: %i[create], shallow: true
  end
  resources :shops, only: %i[index show new create edit update] do
    post :credential, to: "shop_credentials#create"
    delete "credentials/:id", to: "shop_credentials#destroy", as: :credential_revoke
    get "credentials/show_once", to: "shop_credentials#show_once", as: :credential_show_once
  end

  resources :payments, only: %i[index show] do
    resource :timeline, only: :show, controller: "payment_timelines"
    member do
      post :refund
      post :void
    end
  end

  resources :team, only: %i[index new create destroy]

  namespace :admin do
    resources :users, only: %i[index new create] do
      member do
        patch :unlock
        patch :update_role
      end
    end
  end

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
