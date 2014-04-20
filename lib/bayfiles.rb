require 'faraday'
require 'json'
require 'logger'

class BayFiles

  USER = 'yucky'

  PASSWORD = 'he7X6zmJwYHkBGNNkF5g'

  def upload(file)
    resp = JSON.parse(Faraday.get("http://api.bayfiles.net/v1/account/login/#{USER}/#{PASSWORD}").body)
    raise 'error authentication' if resp['error'] != ''
    session = resp['session']
    resp = JSON.parse(Faraday.get("http://api.bayfiles.net/v1/file/uploadUrl?session=#{session}").body)
    raise 'error getting urls' if resp['error'] != ''
    upload_url = resp['uploadUrl']
    process_url = resp['progressUrl']
    payload = { :file => Faraday::UploadIO.new(file, 'application/zip+epub') }
    parts = upload_url.split('/')
    last = parts[-1]
    first = parts[0..-2].join('/')
    conn = Faraday.new(upload_url) do |f|
      f.request :multipart
      f.request :url_encoded
      f.adapter :net_http # This is what ended up making it work
    end
    resp = JSON.parse(conn.post(upload_url, payload).body)
    # {"error":"","fileId":"136tZ","size":"11470","sha1":"3b092c995d76725b7e9cdcc4e5efc3bf89e37d12","infoToken":"cDujpU","deleteToken":"g3dlwRKU","linksUrl":"http:\/\/bayfiles.net\/links\/136tZ\/g3dlwRKU","downloadUrl":"http:\/\/bayfiles.net\/file\/136tZ\/cDujpU\/book.epub","deleteUrl":"http:\/\/bayfiles.net\/del\/136tZ\/g3dlwRKU"}
    return {
      :file_id => resp['fileId'],
      :size => resp['size'],
      :sha1 => resp['sha1'],
      :info_token => resp['infoToken'],
      :delete_token => resp['deleteToken'],
      :links_url => resp['linksUrl'],
      :download_url => resp['downloadUrl'],
      :delete_url => resp['deleteUrl']
    } if resp['error'] == ''
  end

end
