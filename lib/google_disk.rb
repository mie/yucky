require 'google_drive'
require 'oauth2'
require 'json'

class GoogleDrive

  CLIENT_ID = ""
  CLIENT_SECRET = ""
  REDIRECT_URI = "urn:ietf:wg:oauth:2.0:oob"
 
  @file = "db.json"
 
  def client
    if CLIENT_ID.empty?
      puts "First you need to create oauth client information in https://code.google.com/apis/console/"
      exit 1
    end
    OAuth2::Client.new(
    CLIENT_ID, CLIENT_SECRET,
    :site => "https://accounts.google.com",
    :token_url => "/o/oauth2/token",
    :authorize_url => "/o/oauth2/auth")
  end
 
  def authorize
    auth_url = client.auth_code.authorize_url(
      :redirect_uri => REDIRECT_URI,
      :scope =>
        ["https://docs.google.com/feeds/",
        "https://docs.googleusercontent.com/",
        "https://spreadsheets.google.com/feeds/"].join(" "))

    puts "Access in your browser: #{auth_url}"
    print "And please input authorization code: "
    authorization_code = $stdin.gets
     
    auth_token = client.auth_code.get_token(
    authorization_code, :redirect_uri => REDIRECT_URI)
     
    puts "access token: #{auth_token.token}"
    puts "refresh token: #{auth_token.refresh_token}"
    token_hash = {
    :access_token => auth_token.token,
    :refresh_token => auth_token.refresh_token,
    :expires_at => auth_token.expires_at,
    }
     
    open(@file, 'w'){|f| f.print token_hash.to_json }
    puts "write token information in #{@file}"
  end
 
  def login
    token_hash = JSON.parse(File.read(@file))
    access_token = OAuth2::AccessToken.from_hash(client, token_hash.dup)
    access_token.refesh! if Time.now.to_i > access_token.expires_at
    session = GoogleDrive.login_with_oauth(access_token)
  end

end

# if ARGV[0]
# session = login
# # ... write what you want using google drive session
# else
# authorize
# end