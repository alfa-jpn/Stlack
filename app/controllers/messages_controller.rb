class MessagesController < ApplicationController
  before_action :set_keyword, only: [:show]
  before_action :set_type,    only: [:show]
  before_action :set_histories

  HISTORY_CACHE_KEY = 'Views::Keywords::History'

  # GET /
  def index

  end

  # GET /all
  # GET /user/*
  # GET /messages/*
  def show
    respond_to do |format|
      format.json do
        search_message_in_open_channel(count: 128).tap do |messages|
          render 'messages/_partials/_messages', locals: { messages: messages }
        end
      end
      format.html do
        if @type.present? and @keyword.present?
          search_message_in_open_channel(query: @type.create_query(@keyword)).tap do |messages|
            @messages = messages
            if @messages.any? and @histories.none? { |h| h[:type] == @type.downcase and h[:keyword] == @keyword }
              Rails.cache.write(HISTORY_CACHE_KEY, @histories.unshift({ type: @type.downcase, keyword: @keyword }).take(50))
            end
          end
        else
          search_message_in_open_channel.tap do |messages|
            @messages = messages
          end
        end
      end
    end
  rescue RuntimeError => e
    if e.message == 'user_is_bot'
      render :token_error
    else
      raise
    end
  end

  # GET /callback
  def registration_token
    auth = OAuth.find(
      client_id:     Stalck.config.slack.client_id,
      client_secret: Stalck.config.slack.client_secret_key,
      code:          params['code'],
      redirect_uri:  oauth_callback_url
    )

    if auth.team_id == Stalck.config.slack.team_id
      Stalck.config.slack.searchable_token = auth.access_token
      redirect_to root_path
    else
      raise "#{auth.team_name} is not permitted team."
    end
  end

  private
  # Set `@keyword`
  def set_keyword
    @keyword = params[:keyword].try(:strip)
  end

  # Set `@histories`
  def set_histories
    @histories = Rails.cache.read(HISTORY_CACHE_KEY) || []
  end

  # Set `@type`
  def set_type
    @type = MessageSearchers::Type.parse(params[:type])
  end

  # Search newly messages in open channel.
  # @param [String]  query Query.
  # @param [Integer] count Get count.
  # @return <MessageSearcher> result.
  def search_message_in_open_channel(query: 'after:yesterday', count: 20)
    params = {query: query,count: count , sort: :timestamp}
    Rails.cache.fetch("Messages::#{Digest::MD5.hexdigest(params.to_json)}", expires_in: 5.seconds) do
      MessageSearcher.search(params.merge(token: Stalck.config.slack.searchable_token)).messages.select do |message|
        if (id = message.channel.try(:[], 'id')).present?
          (id.first == 'C' && Channel.find_by_id(id).present?)
        else
          false
        end
      end
    end
  end
end
