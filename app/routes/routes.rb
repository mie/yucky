class Yucky < Sinatra::Application

  get '/' do
    redirect '/dashboard' if current_user
    slim :index
  end

  get '/dashboard' do
    redirect '/' unless current_user
    slim :dashboard, :locals => {:books => current_user.books.all}
  end

  get '/signup' do
    slim :signup, :locals => {:type => params['type']}
  end

  get '/epubs/:rid' do
    protected!

    id = params[:rid]
    
    ebook = Book.where(reddit_id: id).first
    redirect '/?not_found' unless ebook
    content_type 'application/epub+zip'
    File.read(File.join('epubs', id, 'book.epub'))
  end

  post '/job' do
    content_type :json
    data = JSON.parse(params.keys[0])
    protected!
    url = data['link']
    m = /https?:\/\/www\.reddit\.com\/r\/([\w\d]+)\/comments\/([\w\d]+{6,})\/(.+)/.match(url)
    return json_status('400', 'Bad link sent') unless m

    subreddit, reddit_id, thread_name = m[1..3]

    Book.delete_all
    # ^^^^^

    books = Book.any_of({:reddit_id => reddit_id, :thread_name => thread_name, :subreddit => subreddit})
    if books.count > 0
      book = books.first
      current_user.add_book(book)
      if book.done
        status 200
        body(JSON.generate({:name => book.save_name}))
      else
        status 200
        body(JSON.generate({:status => 'Book already added to queue'}))
      end
    else
      sn = thread_name+'_'+reddit_id
      book = Book.new({:reddit_id => reddit_id, :save_name => sn, :thread_name => thread_name, :subreddit => subreddit})
      current_user.add_book(book)
      status 200
      body(JSON.generate({:status => 'Book added to queue'}))
    end
  end

  # --------------
  # Authentication
  # --------------

  post '/u/signin' do
    halt [400, "Incomplete parameters"] unless params['email'] && params['password']

    users = User.where(email: params['email'])
    halt [400, "Bad data sent"] unless users.count > 0

    user = users.first

    halt [404, "No user found"] unless validate_password(params['password'], user.password)

    cookies[:tkn] = user.token
    redirect '/'
  end

  post "/u/signup" do
    User.delete_all
    
    halt [400, "Incomplete parameters"] unless ['password', 'email'].all? {|o| params[o] && params[o] != ''}

    email = params['email']
    halt [400, "Wrong email"] unless (email.size > 6 && /\w[\w\d_]+@[\w\d\-]+\.\w{2,5}/.match(email))

    password = params['password']
    halt [400, "Weak password"] unless (password.size > 5)# && /[\w\d_]+/.match(password))

    users = User.where({:email => email})
    halt [400, "Email already used"] unless users.count == 0

    user = User.new({:email => email})
    user.password = create_hash(params['password'])
    user.token = Digest::SHA2.hexdigest("--#{user.password}--")
    
    halt [500, "Server-side error"] unless user.save

    redirect '/?signup_ok'
  end

  delete "/u/signout" do
    content_type :json
    protected!
    cookies.clear
    
    json_status 200, "OK"
  end

end