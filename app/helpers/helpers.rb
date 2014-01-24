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

  end

end