Spinrail.routes.draw do
  root "translations#index"
  get "/translation/edit", to: "translations#edit", as: :edit_translation
  patch "/translation", to: "translations#update", as: :translation
end
