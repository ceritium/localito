Spinrail.routes.draw do
  root "translations#index"
  get "/key", to: "translations#show", as: :key
  get "/keys/new", to: "translations#new", as: :new_key
  post "/keys", to: "translations#create", as: :keys
  patch "/translation", to: "translations#update", as: :translation
  get "/diff", to: "translations#diff", as: :diff
  get "/version", to: "translations#version", as: :version
  get "/export", to: "translations#export", as: :export
  get "/import", to: "translations#import", as: :import
  post "/import", to: "translations#preview_import", as: :preview_import
  post "/import/apply", to: "translations#apply_import", as: :apply_import
  get "/config", to: "translations#settings", as: :settings
end
