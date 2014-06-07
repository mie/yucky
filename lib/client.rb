require_relative 'text'

require "find"
require "json"
require "uri"
require "faraday"
require "faraday_middleware"
require "gepub"
require "erb"
require "thread"
require "fileutils"
require "mongoid"
require "mongoid-pagination"
require "cgi"
require "date"

require_relative File.join('..', 'app', 'models', 'book.rb')

Mongoid.load!("config/mongoid.yml", :development)

class RedditClient

  def initialize(dirname="epubs")
    @conn = Faraday.new(:url => 'http://www.reddit.com') do |faraday|
      faraday.request  :url_encoded             # form-encode POST params
      #faraday.response :logger                  # log requests to STDOUT
      faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
    end
    @conn.headers[:user_agent] = 'reddit reader by /u/_siomi'
    @template_dir = File.join('.', 'templates')
    @last_call = Time.now
    @comments = []
    @base_dir = Dir[dirname]

    @threads = []
    @q = Queue.new
  end

  def perform(options={})
    @running = true
    4.times do |i|
      @threads << Thread.new{
        loop do
          if @q.empty?
            break unless @running
            sleep(2)
          else
            url, save_as = @q.pop
            # unless File.exist?(save_as)
            puts File.expand_path(save_as)
            c = Faraday.new do |conn|
              conn.options[:timeout] = 30
              conn.options[:open_timeout] = 30
              conn.adapter Faraday.default_adapter
              # conn.use FaradayMiddleware::FollowRedirects, limit: 4
            end
            begin
              bin = c.get(url).body
              File.open(save_as, 'wb') { |fp| fp.write(bin) }
            rescue Faraday::Error::TimeoutError => e
              puts "Downloading failed: timeout error"
            end
            # end
            puts "Downloading #{url} to #{save_as} in thread #{i}"
          end
        end
      }
    end

    ['subreddit', 'reddit_id', 'thread_name', 'only_first', 'with_images'].each {|i| instance_variable_set("@#{i}".to_sym, options[i]) }

    # subreddit = options["subreddit"] if options["subreddit"]
    # reddit_id = options["reddit_id"] if options["reddit_id"]
    # thread_name = options["thread_name"] if options["thread_name"]

    @book_dir = File.join(@base_dir, @reddit_id)
    Dir.mkdir(@book_dir) unless File.exists?(@book_dir)

    @url = "http://www.reddit.com/r/#{@subreddit}/comments/#{@reddit_id}/#{@thread_name}/"

    data = JSON.parse(get(@url + '.json?sort=top'))

    root = data[1]
    
    @link_id = data[0]['data']['children'][0]['data']['name']
    @op = OP.new(data[0]['data']['children'][0]['data'])
    
    get_html_images(@op)
    @comments << @op
    
    copy_dir(@template_dir, @book_dir)
    
    parse_comments(root, @op, 0)

    @running = false
    @threads.each {|thr| thr.join }
    build_book
    return @op
    #upload_book
  end

  private

  def parse_comments(root, parent, level)
    root['data']['children'].map { |d|
      if d['kind'] == 't1'
        c = Comment.new(d['data'])
        parent.children.push(c)
        @comments.push(c) unless @only_first # unshift ?
        get_html_images(c)
        parse_comments(d['data']['replies'], c, level+1) unless @only_first || d['data']['replies'] == ''
      elsif d['kind'] == 'more'
        dd = get_more(d['data'])
      end
    } if root['data'] && root['data']['children'] && level < 4
  end

  def get_more(data)
    data['children'].each_slice(20){ |c|
      params = {:api_type => 'json',:children => c.join(','),:link_id => @link_id, :sort => 'top'}
      data = nil
      begin
        data = JSON.parse(rpost('/api/morechildren.json', params))
      rescue JSON::ParserError
        puts 'reddit heavy load'
      end
      if data
        cm = data['json']['data']['things'].map { |c| 
          com = Comment.new(c['data'])
          get_html_images(com)
          com
        }
        @comments += cm unless @only_first
        cm.each { |c| 
          parent = get_parent(c.parent_id)
          # parent.children.push(c)
          parent.add_child(c) if parent
        }
      end
    }
    #JSON.parse(rpost('/api/morechildren', {:api_type => 'json',:children => data['children'].map{|h| 't1_'+h}.join(','),:link_id => @link_id}))
  end

  def build_book
    gen_html

    book_data = {
      :title => @op.title,
      :subtitle => "/r/#{@subreddit}, by #{@op.author}",
      :author => @op.author,
      :date => Time.now.to_s,
      :directory => @book_dir,
      :id => @reddit_id
    }

    builder = GEPUB::Builder.new {
      language 'en'
      unique_identifier book_data[:id]
      #unique_identifier 'http://example.jp/bookid_in_url', 'BookID', 'URL'
      title book_data[:title]
      subtitle 'This book is just a sample'

      creator book_data[:author]

      # contributors 'Denshobu', 'Asagaya Densho', 'Shonan Densho Teidan', 'eMagazine Torutaru'

      date book_data[:date]

      resources(:workdir => book_data[:directory]) {
        
        glob 'css/*.css'

        glob 'images/*.jpg'
        glob 'images/*.jpeg'
        glob 'images/*.png'
        glob 'images/*.gif'

        glob 'fonts/*.otf'
        
        #cover_image 'img/image1.jpg' => 'image1.jpg'
        # file 'fonts/Andada-Regular.otf'
        # id 'Andada-Regular'

        ordered {
          file 'out.html'
          heading book_data[:title]
        }
      }
    }
    epubname = File.join(@book_dir, "book.epub")
    builder.generate_epub(epubname)
    command = Thread.new do
      system("#{File.join('vendor', 'kindlegen')} #{epubname}")
      # system("ebook-convert #{epubname} book.azw3")
    end
    command.join 
  end

  def gen_html
    template = File.read(File.join(@book_dir, 'book.erb'))
    File.open(File.join(@book_dir, 'out.html'), 'w'){ |f| f.write(ERB.new(template).result(binding)) }
  end

  def get_html_images(comment)
    return nil unless @with_images
    comment.extract_links.each{ |i|
      unless i.nil?
        puts i
        case i[:type]
          when :direct
            bget(i[:link], File.join(@book_dir, 'images', i[:filename]))
            # tp = "<figure><img src='images/#{i[:filename]}'></img><figcaption><a href='#{i[:link]}'>#{i[:text]}</a></figcaption></figure>"
            # b[i[:html]] = tp
          when :youtube
            bget("https://img.youtube.com/vi/#{i[:id]}/hqdefault.jpg", File.join(@book_dir, 'images', i[:filename]))
            # tp = "<figure><img src='images/#{i[:filename]}'></img><figcaption><a href='#{i[:link]}'>#{i[:text]}</a></figcaption></figure>"
            # b[i[:html]] = tp
          when :album
            out = []
            b = comment.html.clone
            get("http://imgur.com/a/#{i[:id]}/noscript").scan(/<img src="(\/\/i\.imgur\.com\/([a-zA-Z0-9]+\.(jpg|jpeg|png|gif)))"/) { |img|
              saveas = comment.name+img[0].split('/')[-1]
              bget(img[0], File.join(@book_dir, 'images', saveas))
              tp = "<a href='#{img[0]}'><img src='images/#{saveas}'></img></a>"
              out.push(tp)              
            }
            p b, i[:html]
            CGI.unescapeHTML(b)[i[:html]] = "<p>#{i[:text]}</p>"+out.join
            comment.html = b
        end
      end
    }
    
    
  end

  def copy_dir(source_path, target_path)
    Find.find(source_path) do |source|
      target = source.sub(/^#{source_path}/, target_path)
      if File.directory? source
        FileUtils.mkdir target unless File.exists? target
      else
        FileUtils.copy source, target
      end
    end
  end

  def rpost(path, data)
    # for more_children
    puts 'getting more children'
    sleep(2) if (Time.now - @last_call < 2)
    out = @conn.post(path, data).body
    @last_call = Time.now
    out
  end

  def bget(url, save_as)
    @q.push([url, save_as])
  end

  def get(path)
    @conn.get(path).body
  end

  def get_parent(parent_id)
    com = @comments.select {|c| parent_id == c.name }
    return com[0] if com
    nil
  end

end

c = RedditClient.new
puts "started at #{Time.now}"
loop {
  book = Book.where(status: 'queued').asc(:submitted_at).first
  if book
    puts "Got new job: #{book.reddit_id}"
    op = c.perform({'reddit_id' => book.reddit_id, 'subreddit' => book.subreddit, 'thread_name' => book.thread_name, 'only_first' => book.only_first, 'with_images' => book.with_images})
    book.status = 'done'
    book.finished_at = Time.now

    [:subreddit, :thumbnail, :over_18, :url, :title, :author, :score, :num_comments, :created_utc].each { |m|
      book.send("#{m}=".to_sym, op.send("#{m}".to_sym))
    }

    book.epub_size = File.new(File.join('epubs', book.reddit_id, 'book.epub')).size
    book.mobi_size = File.new(File.join('epubs', book.reddit_id, 'book.mobi')).size
    book.save
    puts "Done job: #{book.reddit_id}"
    
  else
    sleep(1)
  end
}