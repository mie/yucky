require_relative 'authentication'

Yucky.helpers Authentication

class Yucky < Sinatra::Application

  helpers do

    def json_status(code, reason)
      status code
      {
        :status => code,
        :reason => reason
      }.to_json
    end

    def protected!
      halt [401, 'Not Authorized'] unless current_user
    end

    def current_user
      @current_user ||= User.where(:token => cookies[:tkn]).first if cookies[:tkn]
    end

    def g_client
      OAuth2::Client.new(
        G_CLIENT_ID, G_CLIENT_SECRET,
        :site => "https://accounts.google.com",
        :token_url => "/o/oauth2/token",
        :authorize_url => "/o/oauth2/auth"
      )
    end

    def g_authorize
      auth_url = g_client.auth_code.authorize_url(
        :redirect_uri => G_REDIRECT_URI,
        :scope =>
          [
            "https://www.googleapis.com/auth/drive.file"
          ].join(" ")
      )
    end

    # https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=586299000268.apps.googleusercontent.com&redirect_uri=http%3A%2F%2Fwww.gutenberg.org%2Febooks%2Fsend%2Fgdrive%2F&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.file&state=dvOkHiSbCVudxmUJ2yfehwKPScVZKZ

    def g_token_hash(code)
      auth_token = g_client.auth_code.get_token(code, :redirect_uri => @redirect_uri)
      {
        :access_token => auth_token.token,
        :refresh_token => auth_token.refresh_token,
        :expires_at => Time.now.to_i + auth_token.expires_at,
      }
    end
     
    def g_login(token_data)
      access_token = OAuth2::AccessToken.from_hash(g_client, token_data)
      access_token.refresh! if Time.now.to_i > access_token.expires_at
      session = GoogleDrive.login_with_oauth(access_token)
    end

    def g_upload_file(hash, file, name)
      session = g_login(hash)
      status = session.upload_from_file(file, name, :convert => false)
    end

  end

end