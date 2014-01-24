require File.join(File.dirname(__FILE__), 'web')

set :environment, :development
set :port, 9393

run Yucky.new