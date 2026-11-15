Spinrail.routes.draw do
  root "translations#index"
  get "/translation/edit", to: "translations#edit", as: :edit_translation
  get "/changes", to: "translations#changes", as: :changes
  patch "/translation", to: "translations#update", as: :translation
end
