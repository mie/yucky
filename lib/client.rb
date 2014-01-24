require_relative 'text'
require_relative 'bayfiles'

require 'find'
require "json"
require "uri"
require "faraday"
require "faraday_middleware"
require "gepub"
require "erb"
require "thread"
require "fileutils"
require "mongoid"
require 'cgi'


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
    @threads = []
    @comments = []
    @dirname = Dir[dirname]

    @q = Queue.new
    @running = true
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
            unless File.exist?(save_as)
              c = Faraday.new do |conn|
                conn.options[:timeout] = 30
                conn.options[:open_timeout] = 30
                conn.use FaradayMiddleware::FollowRedirects, limit: 4
              end
              bin = c.get(url).body
              File.open(save_as, 'wb') { |fp| fp.write(bin) }
            end
            puts "Downloading #{url} to #{save_as}"
          end
        end
      }
    end
    subreddit = options["subreddit"] if options["subreddit"]
    reddit_id = options["reddit_id"] if options["reddit_id"]
    thread_name = options["thread_name"] if options["thread_name"]
    @dir = File.join(@dirname, reddit_id)
    Dir.mkdir(@dir) unless File.exists?(@dir)

    @url = "http://www.reddit.com/r/#{subreddit}/comments/#{reddit_id}/#{thread_name}/"

    data = JSON.parse(get(@url + '.json?sort=top'))

    root = data[1]
    
    @link_id = data[0]['data']['children'][0]['data']['name']
    @op = OP.new(data[0]['data']['children'][0]['data'])
    
    get_html_images(@op)

    @comments << @op
    
    copy_dir(@template_dir, @dir)
    
    parse_comments(root, @op)
    @running = false
    @threads.each {|thr| thr.join }
    build_book
    #upload_book
  end

  private

  def parse_comments(root, parent)
    root['data']['children'].map { |d|
      if d['kind'] == 't1'
        c = Comment.new(d['data'])
        parent.children.push(c)
        @comments.push(c)
        get_html_images(c)
        #get_images(c)
        parse_comments(d['data']['replies'], c) unless d['data']['replies'] == ''
      elsif d['kind'] == 'more'
        dd = get_more(d['data'])
      end
    } if root['data'] && root['data']['children']
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
        @comments += data['json']['data']['things'].map { |c| 
          com = Comment.new(c['data'])
          get_html_images(com)
          com
        }
        t = data['json']['data']['things'].size
        @comments[-1*(t+1)..-1].each { |c| 
          parent = get_parent(c.parent_id)
          parent.children.push(c)
        }
      end
    }
    #JSON.parse(rpost('/api/morechildren', {:api_type => 'json',:children => data['children'].map{|h| 't1_'+h}.join(','),:link_id => @link_id}))
  end

  def build_book
    # @dir
    gen_html

    t = @op.title
    d = Time.now.to_s
    a = @op.author
    dir = @dir
    
    builder = GEPUB::Builder.new {
      language 'en'
      unique_identifier 'http:/example.jp/bookid_in_url', 'BookID', 'URL'
      title t
      # subtitle 'This book is just a sample'

      creator a

      # contributors 'Denshobu', 'Asagaya Densho', 'Shonan Densho Teidan', 'eMagazine Torutaru'

      date d

      resources(:workdir => dir) {
        
        glob 'css/*.css'

        glob 'images/*.jpg'
        glob 'images/*.jpeg'
        glob 'images/*.png'
        glob 'images/*.gif'
        
        #cover_image 'img/image1.jpg' => 'image1.jpg'
        file 'fonts/Andada-Regular.otf'
        id 'Andada-Regular'

        ordered {
          file 'out.html'
          heading t
        }
      }
    }
    epubname = File.join(@dir, "book.epub")
    builder.generate_epub(epubname)
  end

  def upload_book

  end

  def gen_html
    template = File.read(File.join(@dir, 'book.erb'))
    File.open(File.join(@dir, 'out.html'), 'w'){ |f| f.write(ERB.new(template).result(binding)) }
  end

  def get_html_images(comment)
    b = comment.html.clone

    puts "images : #{comment.html_images.size}"
    comment.html_images.each{ |i|
      unless i.nil?
        puts i
        out = []
        case i[:type]
          when :direct
            bget(i[:link], File.join(@dir, 'images', i[:filename]))
            tp = "<figure><img src='images/#{i[:filename]}'></img><figcaption><a href='#{i[:link]}'>#{i[:text]}</a></figcaption></figure>"
            b[i[:html]] = tp# "#{i[:text]}<img src='images/#{i[:filename]}'></img>"
            #b.gsub!('i[:html]', "#{i[:text]}<img src='images/#{i[:filename]}'></img>")
          when :youtube
            bget("https://img.youtube.com/vi/#{i[:id]}/hqdefault.jpg", File.join(@dir, 'images', i[:filename]))
            tp = "<figure><img src='images/#{i[:filename]}'></img><figcaption><a href='#{i[:link]}'>#{i[:text]}</a></figcaption></figure>"
            b[i[:html]] = tp# "#{i[:text]}<img src='images/#{i[:filename]}'></img>"
            #b.gsub!('i[:html]', "#{i[:text]}<img src='images/#{i[:filename]}'></img>")
          when :album
            out = []
            get("http://imgur.com/a/#{i[:id]}/noscript").scan(/<img src="(\/\/i\.imgur\.com\/([a-zA-Z0-9]+\.(jpg|jpeg|png|gif)))"/) { |img|
              saveas = comment.name+img[0].split('/')[-1]
              bget(img[0], File.join(@dir, 'images', saveas))
              tp = "<figure><img src='images/#{saveas}'></img><figcaption><a href='#{img[0]}'>image</a></figcaption></figure>"
              out.push(tp)
              #out.push("<img src='images/#{saveas}'></img>")
              #b.gsub!('i[:html]', "#{i[:text]}<img src='images/#{saveas}'></img>")
            }
            b[i[:html]] = "<p>#{i[:text]}</p>"+out.join
        end
      end
    }
    comment.html = b
    
  end


  # def get_images(comment)
  #   b = comment.body.clone

  #   comment.images.each{ |i|
  #     unless i.nil?
  #       out = []
  #       case i[:type]
  #         when :direct
  #           bget(i[:link], File.join(@dir, 'images', i[:filename]))
  #           b[i[:md]] = "![#{i[:text]}](images/#{i[:filename]})"
  #           #b.gsub!('i[:md]', "![#{i[:text]}](images/#{i[:filename]})")
  #         when :youtube
  #           bget("https://img.youtube.com/vi/#{i[:id]}/hqdefault.jpg", File.join(@dir, 'images', i[:filename]))
  #           b[i[:md]] = "![#{i[:text]}](images/#{i[:filename]})"
  #           #b.gsub!('i[:md]', "![#{i[:text]}](images/#{i[:filename]})")
  #         when :album
  #           out = []
  #           get("http://imgur.com/a/#{i[:id]}/noscript").scan(/<img src="(\/\/i\.imgur\.com\/([a-zA-Z0-9]+\.(jpg|jpeg|png|gif)))"/) { |img|
  #             saveas = comment.name+img.split('/')[-1]
  #             bget(img, File.join(@dir, 'images', saveas))
  #             out.push("![#{i[:text]}](images/#{saveas})")
  #             #b.gsub!('i[:md]', "![#{i[:text]}](images/#{saveas})")
  #           }
  #           b[i[:md]] = "![#{i[:text]}](images/#{saveas})"
  #       end
  #     end
  #   }
  #   comment.body = b


    # comment.images[:direct].each { |link, v|
    #   bget(v[:download], File.join('epubs', @op.name, 'images', v[:save]))
    #   comment.body = comment.body.sub(v[:md], "![](images/#{v[:save]})")
    # }
    # comment.images[:album].each { |link, v|
    #   out = []
    #   get(v[:url]+'/noscript').scan(/<img src="(\/\/i\.imgur\.com\/([a-zA-Z0-9]+\.(jpg|jpeg|png|gif)))"/) { |img|
    #     saveas = comment.name+img.split('/')[-1]
    #     while @threads.size >= 4
    #       sleep(1)
    #     end
    #     bget(img, File.join('epubs', @op.name, 'images', saveas))
    #     out.push("![Image #{out.size}](images/#{saveas})")
    #   }
    #   comment.body = comment.body.sub(v[:md], out.join(' '))
    # }
  # end

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

  def rget(path, data)
    # get reddit json
    puts "getting reddit json"
    sleep(2) if (Time.now - @last_call < 2)
    out = @conn.get(path, data).body
    @last_call = Time.now
    out
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
    # @threads << Thread.new {
    #   p " ----->>>  #{url}"
    #   unless File.exist?(save_as)
    #     bin = @conn.get(url).body
    #     File.open(save_as, 'wb') { |fp| fp.write(bin) }
    #   end
    # }
  end

  def get(path)
    @conn.get(path).body
  end

  def get_parent(parent_id)
    com = @comments.select {|c| parent_id == c.name }
    return com[0] if com
  end

end

# r = Redis.new
c = RedditClient.new
puts "started at #{Time.now}"
loop {
  book = Book.where(done: false).asc(:submitted_at).first
  if book
    puts "Got new job: #{book.reddit_id}"
    c.perform({'reddit_id' => book.reddit_id, 'subreddit' => book.subreddit, 'thread_name' => book.thread_name})
    book.done = true
    book.finished_at = Time.now
    book.save
    puts "Done job: #{book.reddit_id}"
  else
    sleep(1)
  end
}