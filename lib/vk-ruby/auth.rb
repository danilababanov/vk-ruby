# encoding: UTF-8

module VK::Auth
  attr_accessor :access_token, :expires_in

  DEFAULT_CLIENT_REDIRECT_URL = 'https://oauth.vk.com/blank.html'.freeze

  def authorized?
    !!access_token
  end

  def access_token
    @access_token || config.access_token
  end

  def authorization_url(params)
    app_id = params[:app_id] || config.app_id
    settings = params[:scope] || params[:settings] || config.settings
    version = params[:v] || params[:version] || config.version
    redirect_url = params[:redirect_uri] || params[:redirect_url] || config.redirect_url
    display = params[:display] || :page

    redirect_url ||= DEFAULT_CLIENT_REDIRECT_URL if params[:type] == :client

    fail(ArgumentError, 'You should pass :app_id parameter')       unless app_id
    fail(ArgumentError, 'You should pass :redirect_url parameter') unless redirect_url
    fail(ArgumentError, 'You should pass :settings parameter')     unless settings
    fail(ArgumentError, 'You should pass :version parameter')      unless version

    settings = settings.join(',') if settings.is_a?(Array)
    
    case params[:type]
    when :client, :standalone
      "https://oauth.vk.com/authorize?" << URI.encode_www_form({
        client_id: app_id,
        scope: settings,
        redirect_uri: redirect_url,
        display: display,
        response_type: :token,
        v: version
      })
    when :site, :serverside
      "https://oauth.vk.com/authorize?" << URI.encode_www_form({
        client_id: app_id,
        scope: settings,
        redirect_uri: redirect_url,
        response_type: :token,
        v: version
      })
    end
  end

  # Site authorization
  # {http://vk.com/dev/auth_sites Read more}
  #
  # @param [Hash] code param required for serverside authorization.
  #
  # @raise [VK::AuthorizationError] if vk.com return json with key error.

  def site_auth(params={})
    app_id = params[:app_id] || config.app_id
    app_secret = params[:app_secret] || config.app_secret
    version = params[:version] || config.version
    redirect_url = params[:redirect_url] || config.redirect_url

    fail(ArgumentError, 'You should pass :code parameter')         unless params[:code]
    fail(ArgumentError, 'You should pass :app_id parameter')       unless app_id
    fail(ArgumentError, 'You should pass :app_secret parameter')   unless app_secret
    fail(ArgumentError, 'You should pass :version parameter')      unless version
    fail(ArgumentError, 'You should pass :redirect_url parameter') unless redirect_url

    options = {
      host: 'https://oauth.vk.com',
      client_id: app_id,
      client_secret: app_secret,
      code: params[:code],
      redirect_uri: redirect_url,
      verb: :get,
      v: version
    }

    response = request(options) { |req| req.url "/access_token" }

    self.expires_in = response.body['expires_in']
    self.access_token = response.body['access_token']

    response.body
  end

  # Application server authorization
  # {http://vk.com/dev/auth_server Read more}
  #
  # @param [String] code code param required for serverside authorization.
  #
  # @raise [VK::AuthorizationError] if vk.com return json with key error.

  def server_auth(params={})
    app_id = params[:app_id] || config.app_id
    app_secret = params[:app_secret] || config.app_secret

    fail(ArgumentError, 'You should pass :app_id parameter')     unless app_id
    fail(ArgumentError, 'You should pass :app_secret parameter') unless app_secret

    options = {
      host: 'https://oauth.vk.com',
      client_id: app_id,
      client_secret: app_secret,
      grant_type: :client_credentials,
      verb: :get
    }

    response = request(options) { |req| req.url "/access_token" }

    self.expires_in = 0
    self.access_token = response.body['access_token']

    response.body
  end

  def client_auth(params={})
    app_id = params[:app_id] || config.app_id
    settings = params[:settings] || params[:scope] || config.settings

    fail(ArgumentError, 'You should pass :app_id parameter')   unless app_id
    fail(ArgumentError, 'You should pass :settings parameter') unless settings
    fail(ArgumentError, 'You should pass :login parameter')    unless params[:login]
    fail(ArgumentError, 'You should pass :password parameter') unless params[:password]

    agent = Mechanize.new
    agent.user_agent_alias = 'Mac Safari'

    begin
      agent.get authorization_url(app_id: app_id, settings: settings, type: :client)

      agent.page.form_with(action: /login.vk.com/){ |form|
        form.email = params[:login]
        form.pass  = params[:password]
      }.submit
    rescue Exception => ex
      if ex.is_a?(VK::APIError)
        raise
      else
        raise VK::AuthentificationError.new({
          error: 'Authentification error',
          description: 'invalid loging or password'
        })
      end
    end

    if agent.cookies.detect{|cookie| cookie.name == 'remixsid'}
      sleep 1

      url = agent.page
               .body
               .gsub("\n",'')
               .gsub("  ",'')
               .match(/.*function allow\(\)\s?\{.*}location.href\s?=\s?[\'\"\s](.+)[\'\"].+\}/)
               .to_a
               .last

      agent.get(url)
    else
      raise VK::AuthorizationError.new({
        error: 'Authorization error',
        error_description: 'invalid loging or password'
      })
    end

    sleep 1

    response = agent.page
                    .uri
                    .fragment
                    .split('&')
                    .map{ |s| s.split '=' }
                    .inject({}){ |a, (k,v)| a[k] = v; a }

    self.expires_in = response['expires_in']
    self.access_token = response['access_token']
  end

end
