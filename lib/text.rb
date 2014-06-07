require "nokogiri"

class TextElement

  # attr_reader :id, :name, :author, :ups, :downs, :created_utc, :parent_id
  attr_accessor :parent, :children, :body, :html

  def initialize(json, parent=nil)
    ['id', 'name', 'author', 'ups', 'downs', 'created_utc', 'parent_id'].each {|i|
      name = "@#{i}"
      instance_variable_set(name, json[i])
      self.class.send(:define_method, i) do
        instance_variable_get(name)
      end
    }
    @children = []
  end

  def add_child(c)
    @children << c unless @children.any?{|cl| cl.id == c.id}
  end

  def extract_links
    doc = Nokogiri::HTML.fragment(@html)
    i = 0
    # d = {:direct => [], :youtube => [], :album => []}
    links = doc.css('a').map{ |link|
      m = link['href'].match(/https?:\/\/([^\/]+)\/?([^\)\s]*)/)
      next unless m
      # if r = m[2].match(/(([^\/]+\.(jpg|jpeg|png|gif))[\?\d]*)/)
      if r = m[2].match(/(([^\/]+\.(jpg|jpeg|png))[\?\d]*)/)
        # d[:direct].push({:link => m[0], :filename => "d#{@id}_#{i}.#{r[3]}"})
        out = {:type => :direct, :link => m[0], :filename => "d#{@id}_#{i}.#{r[3]}", :text => link.text.strip, :html => link.to_html}
      elsif m[1] == 'www.youtube.com'
        if r = m[2].match(/v\=([^\&|^#]+)/)
          # d[:youtube].push({:link => m[0], :filename => "y#{@id}_#{i}.jpg"})
          out = {:type => :youtube, :link => m[0], :filename => "y#{@id}_#{i}.jpg", :id => r[1], :html => link.to_html, :text => link.text.strip}
        end
      elsif m[1] == 'youtu.be'
        if r = m[2].match(/([^\?]+)/)
          # d[:youtube].push({:link => m[0], :filename => "y#{@id}_#{i}.jpg"})
          out = {:type => :youtube, :link => m[0], :filename => "y#{@id}_#{i}.jpg", :id => r[1], :html => link.to_html, :text => link.text.strip}
        end
      # elsif m[1] == 'gfycat.com'
      #   if r = m[2].match(/([\w]+)/)
      #     out = {:type => :direct, :link => "http://giant.gfycat.com/#{m[0]}.gif", :filename => "g#{@id}_#{i}.gif", :text => link.text.strip, :html => link.to_html}
      #   end
      elsif m[1] == 'imgur.com'
        if r = m[2].match(/(\w*\/)?([\w\d]+)\#?.*/)
          if !r[1].nil?
            # d[:album].push({:id => r[2], :html => link.to_html, :text => link.text.strip})
            out = {:type => :album, :link => m[0], :id => r[2], :html => link.to_html, :text => link.text.strip}
          else
            # d[:direct].push({:link => "http://i.imgur.com/#{r[2]}.jpg", :filename => "d#{@id}_#{i}.jpg"})
            out = {:type => :direct, :link => "http://i.imgur.com/#{r[2]}.jpg", :filename => "#{@id}_#{r[2]}.jpg", :id => r[2], :html => link.to_html, :text => link.text.strip}
          end
        end
      end
      if out && out[:filename]
        # <figure><img src='images/#{i[:filename]}'></img><figcaption><a href='#{i[:link]}'>#{i[:text]}</a></figcaption></figure>
        figure = doc.document.create_element('div')
        a = doc.document.create_element('a')
        a['href'] = out[:link]
        a.content = link.text.strip
        img = doc.document.create_element('img')
        img['src'] = "images/#{out[:filename]}"
        # link.replace img
        figure.add_child(a)
        figure.add_child(img)
        link.replace(figure)
        @html = doc.to_html
        i += 1
      end
      out
    }
    return links
  end

  def has_children?
    @children.size > 0
  end

  def html_children(lvl=1)
    #  on #{Time.at(@created_utc).strftime('%e %b %Y, %H:%M')}
    score = 1
    if @ups
      score = @ups
      if @downs
        score -= @downs
      end
    end
    # out = "<li><div class='comment#{' bad' if score<0}  '><h6 class='user'>#{score} | by #{@author}</h6>#{CGI.unescapeHTML(@html)}</div>"
    # out += "<ul class='nested'>"+@children.map { |child| child.html_children }.join+"</ul>" if has_children?
    # out += "</li>"


    # out = "<div class='branch'><div class='comment#{' bad' if score<0}  '><h6 class='user'>#{score} | by #{@author}</h6>#{CGI.unescapeHTML(@html)}</div>"
    # out += "<div class='nested'>"+@children.map { |child| child.html_children }.join+"</div>" if has_children?
    # out += "</div>"

    out = "<div class='lvl#{lvl<4 ? lvl : '0'}'><div class='comment#{' bad' if score<0}  '><h6 class='user'> #{('v'*(lvl-3) + ' |' if lvl > 3)} #{score} | by #{@author}</h6>#{CGI.unescapeHTML(@html)}</div>"
    if has_children?
      out+="<div class='nested'>" if lvl<4
      out+=@children.map { |child| child.html_children(lvl+1) }.join
      out+="</div>" if lvl<4
    end

    out += "</div>"


    out
  end

  def children_list
    out = "<li><div class='second comment'><h5 class='epsilon'><i class='score'>#{@score}</i>#{@author}</h5>#{CGI.unescapeHTML(@html)}</div></li>"
    out += @children.map { |child| child.children_list }.join
    out
  end

  def traverse(&block)
    yield self
    @children.each { |child| child.traverse(&block) }
  end

end

class Comment < TextElement

  def initialize(json, parent=nil)
    html = json['body_html']
    @html = html.nil? ? '' : CGI.unescapeHTML(html)
    super
  end

end

class OP < TextElement

  attr_reader :title, :score, :num_comments, :subreddit, :over_18, :thumbnail, :url

  def initialize(json, parent=nil)
    ['title', 'score', 'num_comments', 'subreddit', 'over_18', 'thumbnail', 'url'].each {|i|
      name = "@#{i}"
      instance_variable_set(name, json[i])
      self.class.send(:define_method, i) do
        instance_variable_get(name)
      end
    }
    html = json['selftext_html'].nil? ? '<a href="'+ json['url'] + '">'+json['title']+'</a>' : json['selftext_html']
    @html = CGI.unescapeHTML(html)
    super
  end

  def html_children
    # out = "<h2>#{@title}</h2><div class='op'><h6>#{@score} | #{@author}, on #{Time.at(@created_utc).strftime('%e %b %Y, %H:%M')}</h6>#{@html}</div><hr/>"
    # out += "<ul class='nested'>"+@children.map { |child| child.html_children }.join+"</ul>"
    out = "<h2>#{@title}</h2><div class='op'><h6>#{@score} | #{@author}, on #{Time.at(@created_utc).strftime('%e %b %Y, %H:%M')}</h6>#{@html}</div><hr/>"
    out += "<div class='nested'>"+@children.map { |child| child.html_children }.join+"</div>"
  end

end