class Yucky < Sinatra::Application

  configure :development do
    set :environment, :development
    enable :sessions, :logging, :static, :method_override, :dump_errors, :run
    Mongoid.load!(File.expand_path(File.join("config", "mongoid.yml")))
  end

  configure :test do
    set :environment, :test
    enable :sessions, :static, :method_override, :raise_errors
    disable :run, :dump_errors, :logging
    Mongoid.load!(File.expand_path(File.join("config", "mongoid.yml")))
  end

  configure :production do
    set :environment, :production
    enable :sessions, :logging, :static, :method_override, :dump_errors, :run
    Mongoid.load!(File.expand_path(File.join("config", "mongoid.yml")))
  end

end