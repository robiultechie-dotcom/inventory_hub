# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  post   "session/sign_in",       to: "sessions#create",        as: :sign_in
  get    "session/confirm_email", to: "sessions#confirm_email", as: :confirm_email
  delete "session/sign_out",      to: "sessions#destroy",       as: :sign_out

  # Official OmniAuth 2.0 Callback Routes (Section 3)
  match "/auth/:provider/callback", to: "sessions#omniauth", via: %i[get post], as: :omniauth_callback
  get   "/auth/failure",            to: "sessions#omniauth_failure",             as: :omniauth_failure

  post "preferences/locale", to: "preferences#update_locale", as: :update_locale
  post "preferences/theme",  to: "preferences#update_theme",  as: :update_theme

  get "search",             to: "search#index",       as: :search
  get "search/suggestions", to: "search#suggestions", as: :search_suggestions
  get "tags/autocomplete",  to: "tags#autocomplete",  as: :tags_autocomplete

  post "uploads", to: "uploads#create", as: :uploads

  resources :users, only: %i[show] do
    collection do
      get :autocomplete
    end
  end

  namespace :admin do
    resources :users, only: %i[index] do
      collection do
        post :bulk_action
      end
    end
  end

  resources :inventories, only: %i[index show create update destroy] do
    collection do
      delete :bulk_destroy
      get    :export_csv
    end

    member do
      patch  :update_custom_id
      patch  :update_fields
      post   :grant_access
      delete :revoke_access
      get    :export_items_csv
    end

    resources :items, only: %i[show new create edit update] do
      collection do
        delete :bulk_destroy
      end
      member do
        post :toggle_like
      end
    end

    resources :comments, only: %i[index create]
  end
end
