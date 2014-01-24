require 'sinatra'
require "sinatra/cookies"
require 'mongoid'
require "mongoid-pagination"
# require 'redis'
require 'slim'

require File.join(File.dirname(__FILE__), 'config', 'mongoid.rb')
#require File.join(File.dirname(__FILE__), 'lib', 'client.rb')

class Yucky < Sinatra::Application

  if defined? Encoding
    Encoding.default_external = Encoding::UTF_8
    Encoding.default_internal = Encoding::UTF_8
  end

  set :app_file, __FILE__
  set :root, File.dirname(__FILE__)
  set :default_encoding, 'utf-8'
  set :static, true
  set :views, File.join(settings.root, 'views')
  set :slim, :pretty => true

  enable :sessions
  set :session_secret, '*&(^B234'

end

Dir[File.join(File.dirname(__FILE__), "app", "**", '*.rb')].each do |file|
  require file
end
