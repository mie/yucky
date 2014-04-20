class Yucky < Sinatra::Application

  get '/' do
    msg = {
      'incomplete' => {:txt => 'Authentication error: Incomplete parameters sent', :type => 'danger'},
      'weak' => {:txt => 'Authentication error: Please select a stronger password', :type => 'danger'},
      'incorrect' => {:txt => 'Authentication error: Incorrent email provided', :type => 'danger'},
      'notfound' => {:txt => 'Authentication error: no use found', :type => 'danger'},
      'emailused' => {:txt => 'Authentication error: Provided email is already used', :type => 'danger'},
      'error' => {:txt => 'Server-side error: Please try again later', :type => 'danger'},
      'signup_ok' => {:txt => 'Thank you for signup! Now login to start using AlienReader!', :type => 'success'}
      }[params['m']]
    return slim :index2, :layout => :logged_layout, :locals => {
      :subreddits => current_user.books.distinct(:subreddit).sort, 
      # :dates => current_user.books.distinct(:submitted_string),
      :queued => current_user.books.where(status: 'queued').count,
      :total => current_user.books.all.count
    } if current_user
    slim :index, :locals => {:msg => msg}
  end

  get '/json/books' do
    protected!
    content_type :json
    data = params
    return json_status 400, 'No parameter *page*' unless params['page'] && params['page'].match(/\d+/)
    page = params['page'].to_i
    s = ['date', 'subreddit'].select {|i| data.keys.include?(i) && data[i] != ''}
    #return json_status('400', 'invalid request') if s == []
    query = {:status => 'done'}
    unless s == []
      type = s[0]
      field = {'date' => 'submitted_string', 'subreddit' => 'subreddit'}[type].to_sym
      query.merge!({field => params[type]})
    end
    books = current_user.books.where(query).paginate(:page => page, :limit => 20).desc(:submitted_at).all
    {:books => books}.to_json
  end

  get '/settings' do
    redirect '/' unless current_user
    slim :settings, :layout => :logged_layout
  end

  get '/books/:format/:rid' do
    protected!

    id = params[:rid].split('.')[0]
    
    ebook = Book.where(reddit_id: id).first
    redirect '/?not_found' unless ebook
    current_user.add_book(ebook)

    # if current_user.books.include?(ebook)
    if params['format'] == 'epub'
      content_type 'application/epub+zip'
      attachment "book.epub"
      File.read(File.join('epubs', id, 'book.epub'))
    elsif params['format'] == 'mobi'
      content_type 'application/x-mobipocket-ebook'
      attachment "book.mobi"
      File.read(File.join('epubs', id, 'book.mobi'))
    end
    # else
    #   redirect '/?not_authorised'
    # end
  end

  delete '/books/:rid' do
    protected!
    content_type :json
    id = params[:rid]
    
    ebook = Book.where(reddit_id: id).first
    return {:type => 'error', :txt => 'book not found'} unless ebook
    current_user.del_book(ebook)
    # if current_user.books.include?(ebook)
    ebook.destroy
    {:type => 'success', :txt => 'deleted successfully'}.to_json
  end

  post '/job' do
    protected!
    content_type :json
    data = JSON.parse(params.keys[0])
    p data
    protected!
    url = data['link']
    m = /https?:\/\/www\.reddit\.com\/r\/([\w\d]+)\/comments\/([\w\d]+{6,})\/(.+)/.match(url)
    return json_status('400', 'Bad link sent') unless m

    subreddit, reddit_id, thread_name = m[1..3]

    # Book.delete_all
    # ^^^^^

    books = Book.any_of({:reddit_id => reddit_id, :thread_name => thread_name, :subreddit => subreddit})
    if books.count > 0
      book = books.first
      current_user.add_book(book)
      if book.status == 'done'
        status 200
        body(JSON.generate({:name => book.save_name}))
      else
        status 200
        body(JSON.generate({:status => 'Book already added to queue'}))
      end
    else
      sn = thread_name+'_'+reddit_id
      book = Book.new({:reddit_id => reddit_id, :save_name => sn, :thread_name => thread_name, :subreddit => subreddit, :only_first => data['only_first'], :with_images => data['with_images']})
      current_user.add_book(book)
      status 200
      body(JSON.generate({:status => 'Book added to queue'}))
    end
  end

  # --------------
  # Authentication
  # --------------

  post '/u/signin' do
    redirect '/?m=incomplete' unless params['email'] && params['password']

    users = User.where(email: params['email'])
    redirect '/?m=notfound' unless users.count > 0

    user = users.first

    redirect '/?m=notfound' unless validate_password(params['password'], user.password)

    cookies[:tkn] = user.token
    redirect '/'
  end

  post "/u/signup" do
    redirect '?m=incomplete' unless ['password', 'email'].all? {|o| params[o] && params[o] != ''}

    email = params['email']
    redirect '/?m=incorrect' unless (email.size > 6 && /\w[\w\d_]+@[\w\d\-]+\.\w{2,5}/.match(email))

    password = params['password']
    redirect '/?m=weak' unless (password.size > 5)# && /[\w\d_]+/.match(password))

    users = User.where({:email => email})
    redirect '/?m=emailused' unless users.count == 0

    user = User.new({:email => email})
    user.password = create_hash(params['password'])
    user.token = Digest::SHA2.hexdigest("--#{user.password}--")
    
    redirect '/?m=error' unless user.save

    redirect '/?m=signup_ok'
  end

  post '/u/update' do
    protected!
    content_type :json
    out = {}
    data = JSON.parse(params.keys[0])
    p data
    valid = ['email', 'password'].any? {|w| data.keys.include? (w)}
    return {:txt => 'wrong parameter sent', :type => 'danger'}.to_json unless valid
    email = data['email']
    if email
      return {:txt => 'wrong email specified', :type => 'danger'}.to_json unless (email.size > 6 && /\w[\w\d_]+@[\w\d\-]+\.\w{2,5}/.match(email))
      current_user.email = email
    end
    password = data['password']
    if password
      return {:txt => 'weak password', :type => 'danger'}.to_json unless (password.size > 5)
      current_user.password = create_hash(password)
    end
    current_user.save
    {:txt => 'settings updated', :type => 'success'}.to_json
  end

  delete "/u/signout" do
    protected!
    content_type :json
    cookies.clear    
    json_status 200, "OK"
  end

  # ------
  # Search
  # ------

  post '/json/search' do
    protected!
    content_type :json
    data = JSON.parse(params.keys[0])
    s = ['date', 'subreddit'].select {|i| data.keys.include?(i) && data[i] != ''}
    return json_status('400', 'no page specified') unless data['page']
    if data['date']
      d = data['date'].split(' ').map{|g|
        if g.size == 1
          "0#{g}"
        else
          g
        end
      }.join(' ')
      data['date'] = d
    end
    all = true if s == []
    type = s[0]
    page = data['page'].to_i || 1
    books = current_user.books.where({:status => 'done'})
    unless all
      field = {'date' => 'submitted_string', 'subreddit' => 'subreddit'}[type].to_sym
      books = books.where({field => data[type]})
    end
    subreddits = books.distinct(:subreddit).sort
    dates = books.distinct(:submitted_string)
    bs = books.paginate(:page => page, :limit => 8).desc(:finished_at).all
    {:books => bs.all, :subreddits => subreddits, :dates => dates, :query => type}.to_json
  end

  # --------------------------
  # Google Drive authorisation
  # --------------------------

  def '/cloud/?' do
    slim :cloud
  end

end
