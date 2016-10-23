Rails.application.routes.draw do
  root controller: :messages, action: :index
  get '/slack_callback',   controller: :messages, action: :registration_token, as: :oauth_callback
  get '/:type(/:keyword)', controller: :messages, action: :show, constraints: { type: /(all|user|message)/ }, as: :show
end
