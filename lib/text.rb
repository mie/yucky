class Text

  attr_reader :id, :author, :name, :parent_id
  attr_accessor :parent, :children, :body, :html

  def initialize(json, parent=nil)
    @id = json['id']
    @name = json['name']
    @author = json['author']
    @children = []
    @parent_id = json['parent_id']
  end

  def images
    @body.scan(/((\[([^\]]+)\]\()?(https?:\/\/([^\/]+\.\w{2,})\/?([^\)\s]*))\)?)/).map{ |m|
      p m
      if r = m[5].match(/(([^\/]+\.(jpg|jpeg|png|gif))[\?\d]*)/)
        {:type => :direct, :link => m[3], :filename => r[2], :text => m[2], :md => m[0]}
      elsif m[4] == 'www.youtube.com'
        if r = m[5].match(/v\=([^\&]+)/)
          {:type => :youtube, :link => m[3], :filename => "youtube_#{r[1]}.jpg", :id => r[1], :text => m[2], :md => m[0]}
        end
      elsif m[4] == 'imgur.com'
        if r = m[5].match(/(\w*\/)?([\w\d]+)\#?.*/)
          {:type => :album, :link => m[3], :id => r[2], :text => m[2], :md => m[0]}
        end
      end
    }
  end

  def html_images
    return @html.scan(/(<a\shref=\"(https?:\/\/([^\/]+\.\w{2,})\/?([^\)\s]*))\">([^<]+)<\/a>)/).map{ |m|
      if r = m[3].match(/(([^\/]+\.(jpg|jpeg|png|gif))[\?\d]*)/)
        {:type => :direct, :link => m[1], :filename => r[2], :text => m[4], :html => m[0]}
      elsif m[2] == 'www.youtube.com'
        if r = m[3].match(/v\=([^\&]+)/)
          {:type => :youtube, :link => m[1], :filename => "youtube_#{r[1]}.jpg", :id => r[1], :html => m[0], :text => m[4]}
        end
      elsif m[2] == 'youtu.be'
        if r = m[3].match(/([^\?]+)/)
          {:type => :youtube, :link => m[1], :filename => "youtube_#{r[1]}.jpg", :id => r[1], :html => m[0], :text => m[4]}
        end      
      elsif m[2] == 'imgur.com'
        if r = m[3].match(/(\w*\/)?([\w\d]+)\#?.*/)
          if !r[1].nil?
            {:type => :album, :link => m[1], :id => r[2], :html => m[0], :text => m[4]}
          else
            {:type => :direct, :link => "http://i.imgur.com/#{r[2]}.jpg", :filename => "#{r[2]}.jpg", :id => r[2], :html => m[0], :text => m[4]}
          end
        end
      end
    } if has_links?
    []
  end

  def has_children?
    @children.size > 0
  end

  def has_links?
    @body.include?('http://')
  end

  def html_children
    #CGI.unescapeHTML
    out = "<li><div class='comment'><h5 class='epsilon'><i class='score'>#{@score}</i>#{@author}</h4>#{CGI.unescapeHTML(@html)}</div>"
    out += "<ul class='nested'>"+@children.map { |child| child.html_children }.join+"</ul>"
    out += "</li>"

    # out = "<div class='nested'><div class='comment'><h4 class='delta'><i class='score'>#{@score}</i>#{@author}</h4>#{CGI.unescapeHTML(@html)}</div>"
    # out += @children.map { |child| child.html_children }.join
    # out += "</div>"
  end

  def traverse(&block)
    yield self
    @children.each { |child| child.traverse(&block) }
  end

  private

end

class Comment < Text

  def initialize(json, parent=nil)
    @body = json['body'] || ''
    html = json['body_html']
    #html['&'] = '&amp;'
    #@html = HTMLEntities.new.decode(html)
    @html = html.nil? ? '' : CGI.unescapeHTML(html)
    #@html = html.gsub('&lt', '<').gsub('&gt', '>')
    @score = ''#json['ups'] - json['downs']
    super
  end

end

class OP < Text

  attr_reader :title, :url

  def initialize(json, parent=nil)
    @body = json['selftext'] == "" ? json['url'] : json['selftext']
    html = json['selftext_html'].nil? ? '<a href="'+ json['url'] + '">'+json['title']+'</a>' : json['selftext_html']
    #html.gsub('&', '&amp;')
    @html = CGI.unescapeHTML(html)
    #@html = html.gsub('&lt', '<').gsub('&gt', '>')
    @title = json['title']
    @score = json['score']
    @url = json['url']
    super
  end

  def html_children
    #CGI.unescapeHTML
    out = "<h2 class='beta'>#{@title}</h2><div class='op'><h4 class='delta'><i class='score'>#{@score}</i>#{@author}</h4>#{@html}</div>"
    out += "<ul class='nested'>"+@children.map { |child| child.html_children }.join+"</ul>"
  end

end