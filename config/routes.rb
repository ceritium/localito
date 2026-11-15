Spinrail.routes.draw do
  root "translations#index"
  get "/key", to: "translations#show", as: :key
  get "/keys/new", to: "translations#new", as: :new_key
  post "/keys", to: "translations#create", as: :keys
  patch "/translation", to: "translations#update", as: :translation
  get "/diff", to: "translations#diff", as: :diff
  get "/version", to: "translations#version", as: :version
end
