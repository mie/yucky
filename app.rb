# require "redditkit"

# class Client

#   def initialize(l,p)
#     @rk = RedditKit::Client.new l, p
#   end

#   def add_link(url)
#     m = /.*\/r\/([\w\d]+)\/comments\/([\w\d]+)\/.+/.match(url)
#     return nil unless m
#     comments = @rk.comments(m[2])
#     comments
#   end

# end

# c = Client.new('siomi', 'reddit1ns3y3d')
# comms = c.add_link('www.reddit.com/r/IAmA/comments/1tcrxh/we_are_the_glitch_mob_ask_us_anything/')
# comms.each { |com| p com } if comms

require "json"
require "net/http"
require "uri"
require "faraday"
require "gepub"
require "erb"
require "kramdown"
require "tmpdir"

module RedditFetcher

  class Client

    def initialize(url)
      m = /http:\/\/www\.reddit\.com\/r\/([\w\d]+)\/comments\/([\w\d]+)\/.+/.match(url)
      return nil unless m
      @template = File.read(File.join('templates', 'book.erb')) # book.erb
      @url = url[-1] == '/' ? url : url + '/'
      @subreddit = m[1]
      @post_link = m[2]
      @uri = URI.parse(url)
      @conn = Faraday.new(:url => 'http://www.reddit.com') do |faraday|
        faraday.request  :url_encoded             # form-encode POST params
        #faraday.response :logger                  # log requests to STDOUT
        faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
      end
      @last_call = Time.now
      @threads = []
      @comments = []
    end

    def process
      raise 'no url provided' unless @url
      data = File.exist?('json.json') ? JSON.parse(File.read('json.json')) : JSON.parse(get(@url + '.json?sort=top'))
      root = data[1]
      @op = OP.new(data[0]['data']['children'][0]['data'])
      get_images(@op)
      p @op.body
      @comments << @op
      @link_id = data[0]['data']['children'][0]['data']['name']

      dir = File.join('epubs', @op.name)
      Dir.mkdir(dir) unless File.exist?(dir)
      Dir.mkdir(File.join(dir, 'images')) unless File.exist?(File.join(dir, 'images'))
      
      parse_comments(root, 0, @op)
      @threads.each {|thr| thr.join }
      build_book
    end

    def parse_comments(root, tab, parent)
      out = ""
      root['data']['children'].map { |d|
        if d['kind'] == 't1'
          c = Comment.new(d['data'])
          parent.children.push(c)
          @comments.push(c)
          get_images(c)
          parse_comments(d['data']['replies'], tab + 1, c) unless d['data']['replies'] == ''
        elsif d['kind'] == 'more'
          dd = get_more(d['data'])
        end
      } if root['data'] && root['data']['children']
      out
    end

    def get_more(data)
      data['children'].map{ |c|
        params = {:api_type => 'json',:children => c,:link_id => @link_id, :sort => 'top'}
        data = ''
        data = JSON.parse(rpost('/api/morechildren.json', params))
        if data
          @comments += data['json']['data']['things'].map { |c| 
            Comment.new(c['data'])
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
      dir = File.join('epubs', @op.name)
      Dir.mkdir(dir) unless File.exist?(dir)
      gen_html

      t = @op.title
      a = @op.author
      builder = GEPUB::Builder.new {
        language 'en'
        unique_identifier 'http:/example.jp/bookid_in_url', 'BookID', 'URL'
        title t
        subtitle 'This book is just a sample'

        creator a

        contributors 'Denshobu', 'Asagaya Densho', 'Shonan Densho Teidan', 'eMagazine Torutaru'

        date '2012-02-29T00:00:00Z'

        resources(:workdir => dir) {
          #cover_image 'img/image1.jpg' => 'image1.jpg'
          ordered {
            file 'out.html'
            heading 'Chapter 1'
          }
        }
      }
      epubname = File.join(dir, 'example_test_with_builder.epub')
      builder.generate_epub(epubname)
    end

    def gen_html
      b = binding
      File.open(File.join('epubs', @op.name, 'out.html'), 'w'){ |f| f.write(ERB.new(@template).result(b)) }
    end

    def get_images(comment)
      comment.images[:direct].each { |link, v|
        bget(v[:download], File.join('epubs', @op.name, 'images', v[:save]))
        comment.body = comment.body.sub(v[:md], "![](images/#{v[:save]})")
      }
      comment.images[:album].each { |link, v|
        out = []
        get(v[:url]+'/noscript').scan(/<img src="(\/\/i\.imgur\.com\/([a-zA-Z0-9]+\.(jpg|jpeg|png|gif)))"/) { |img|
          saveas = comment.name+img.split('/')[-1]
          while @threads.size >= 4
            sleep(1)
          end
          bget(img, File.join('epubs', @op.name, 'images', saveas))
          out.push("![Image #{out.size}](images/#{saveas})")
        }
        comment.body = comment.body.sub(v[:md], out.join(' '))
      }
    end

    class Text

      attr_reader :id, :author, :name, :parent_id
      attr_accessor :parent, :children, :body

      def initialize(json, parent=nil)
        @json = json
        @id = json['id']
        @name = json['name']
        @author = json['author']
        @images = []
        @children = []
        @parent = parent
        @parent_id = json['parent_id']
      end

      def images
        d = []#get_images.merge(get_youtube.merge(get_imgur))
        a = []#get_imgur_album.merge(get_imgur_gallery)
        {
          :direct => d,
          :album => a
        }
      end

      # def to_s
      #   "#{author}: #{body}\n\n"
      # end

      def has_children?
        @children.size > 0
      end

      def has_links?
        @body.include?('http')
      end

      def get_children
        out = "<ul class='nested'><li><div class='comment'><h3>#{@author}</h3><div class='body'>#{Kramdown::Document.new(@body).to_html}</div></div>"
        out += @children.map { |child| child.get_children }.join
        out += "</li></ul>"
      end

      def traverse(&block)
        yield self
        @children.each { |child| child.traverse(&block) }
      end

      private

      def get_images
        out = {}
        @body.scan(/(\[[^\[]+\]\((https?:\/\/[^\s^\[]*\.(?:png|jpg|gif|jpeg))[^\s\)]*\))/){ |m|
          e = { :url => m[1], :download => m[1], :save => @name+m[1].split('/')[-1], :md => m[0] }
          out[m[1]] = e unless out.keys.include?(e)
        } unless @body.nil?
        @body.scan(/(https?:\/\/[^\s^\[]*\.(?:png|jpg|gif|jpeg))/){ |m|
          e = { :url => m[0], :download => m[0], :save => @name+m[0].split('/')[-1], :md => m[0] }
          out[m[0]] = e unless out.keys.include?(e)
        } unless @body.nil?
        out
      end

      def get_imgur_gallery
        out = {}
        b = @body.gsub(/imgur\.com\/gallery\//, 'imgur.com/a/a')
        b.scan(/(\[[^\[]+\]\(((https?)\:\/\/(www\.)?imgur\.com\/a\/([a-zA-Z0-9]+)(#[0-9]+)?\?[^\s\)]*)\))/){ |m|
          e = { :url => m[1], :code => m[5], :md => m[0] }
          out[m[1]] = e unless out.keys.include?(e)
        } unless @body.nil?
        b.scan(/((https?)\:\/\/(www\.)?imgur\.com\/a\/([a-zA-Z0-9]+)(#[0-9]+)?\?[^\s\)]*)/){ |m|
          e = { :url => m[0], :code => m[4], :md => m[0] }
          out[m[0]] = e unless out.keys.include?(e)
        } unless @body.nil?
        out
      end

      def get_imgur_album
        out = {}
        @body.scan(/(\[[^\[]+\]\(((https?)\:\/\/(www\.)?imgur\.com\/a\/([a-zA-Z0-9]+)(#[0-9]+)?\?[^\s\)]*)\))/){ |m|
          e = { :url => m[1], :code => m[5], :md => m[0] }
          out[m[1]] = e unless out.keys.include?(e)
        } unless @body.nil?
        @body.scan(/((https?)\:\/\/(www\.)?imgur\.com\/a\/([a-zA-Z0-9]+)(#[0-9]+)?\?[^\s\)]*)/){ |m|
          e = { :url => m[0], :code => m[4], :md => m[0] }
          out[m[0]] = e unless out.keys.include?(e)
        } unless @body.nil?
        out
      end

      def get_imgur
        out = {}
        @body.scan(/(\[[^\[]+\]\((https?:\/\/imgur\.com\/([a-zA-Z0-9]+))[^\s\)]*\))/){ |m|
          e = { :url => m[1], :download => "http://i.imgur.com/#{m[2]}.jpg", :save => @name+m[2]+'.jpg', :md => m[0] }
          out[m[1]] = e unless out.keys.include?(e)
        } unless @body.nil?
        @body.scan(/(https?:\/\/imgur\.com\/([a-zA-Z0-9]+))[^\s\)]*/){ |m|
          e = { :url => m[0], :download => "http://i.imgur.com/#{m[1]}.jpg", :save => @name+m[1]+'.jpg', :md => m[0] }
          out[m[0]] = e unless out.keys.include?(e)
        } unless @body.nil?
        out
      end

      def get_youtube
        out = {}

        @body.scan(/(\[[^\[]+\]\((https?:\/\/(?:www\.)?youtu(?:be\.com\/watch\?v=|\.be\/)(\w*)(&(amp;)?[\w\?=]*)?)[^\s\)]*\))/){ |m|
          e = { :url => m[1], :download => "https://img.youtube.com/vi/#{m[2]}/hqdefault.jpg", :save => @name+m[2]+'.jpg', :md => m[0] }
          out[m[1]] = e unless out.keys.include?(e)
        } unless @body.nil?
        @body.scan(/(https?:\/\/(?:www\.)?youtu(?:be\.com\/watch\?v=|\.be\/)(\w*)(&(amp;)?[\w\?=]*)?)/){ |m|
          e = { :url => m[0], :download => "https://img.youtube.com/vi/#{m[1]}/hqdefault.jpg", :save => @name+m[1]+'.jpg', :md => m[0] }
          out[m[0]] = e unless out.keys.include?(e)
        } unless @body.nil?
        out
      end

    end

    class Comment < Text

      def initialize(json, parent=nil)
        @body = json['body']
        super
      end

    end

    class OP < Text

      attr_reader :title, :url

      def initialize(json, parent=nil)
        @body = json['selftext'] == "" ? json['url'] : json['selftext']
        @title = json['title']
        @url = json['url']
        super
      end

    end

    private

    def rget(path, data)
      sleep(2) if (Time.now - @last_call < 2)
      out = @conn.get(path, data).body
      @last_call = Time.now
      out
    end

    def rpost(path, data)
      sleep(2) if (Time.now - @last_call < 2)
      out = @conn.post(path, data).body
      @last_call = Time.now
      out
    end

    def bget(url, save_as)
      @threads << Thread.new {
        p " ----->>>  #{url}"
        bin = @conn.get(url).body
        File.open(save_as, 'wb') { |fp| p " ----->>>  #{save_as}"; fp.write(bin) }
      }
    end

    def get(path)
      @conn.get(path).body
    end

    def get_parent(parent_id)
      com = @comments.select {|c| parent_id == c.name }
      return com[0] if com
    end
  
  end

end

#c = RedditFetcher::Client.new 'http://www.reddit.com/r/AskReddit/comments/1tfmv2/what_is_your_favorite_smell_and_why/', 'template.slim'
c = RedditFetcher::Client.new 'http://www.reddit.com/r/pics/comments/1tzi04/incredible_frozen_sand_formations_forming_along/'
c.process
