require "nokogiri"
require "open-uri"

  def extract_links(html)
    doc = Nokogiri::HTML.parse(html)
    links = doc.css('a').map{ |link|
      m = link['href'].match(/https?:\/\/([^\/]+)\/?([^\)\s]*)/)
      if r = m[2].match(/(([^\/]+\.(jpg|jpeg|png|gif))[\?\d]*)/)
        out = {:type => :direct, :link => m[0], :filename => "#{@id}_#{r[2]}", :text => link.text.strip, :html => link.to_html}
      elsif m[1] == 'www.youtube.com'
        if r = m[2].match(/v\=([^\&]+)/)
          out = {:type => :youtube, :link => m[0], :filename => "#{@id}_youtube_#{r[1]}.jpg", :id => r[1], :html => link.to_html, :text => link.text.strip}
        end
      elsif m[1] == 'youtu.be'
        if r = m[2].match(/([^\?]+)/)
          out = {:type => :youtube, :link => m[0], :filename => "#{@id}_youtube_#{r[1]}.jpg", :id => r[1], :html => link.to_html, :text => link.text.strip}
        end      
      elsif m[1] == 'imgur.com'
        if r = m[2].match(/(\w*\/)?([\w\d]+)\#?.*/)
          if !r[1].nil?
            out = {:type => :album, :link => m[0], :id => r[2], :html => link.to_html, :text => link.text.strip}
          else
            out = {:type => :direct, :link => "http://i.imgur.com/#{r[2]}.jpg", :filename => "#{@id}_#{r[2]}.jpg", :id => r[2], :html => link.to_html, :text => link.text.strip}
          end
        end
      end
      if out && out[:filename]
        # <figure><img src='images/#{i[:filename]}'></img><figcaption><a href='#{i[:link]}'>#{i[:text]}</a></figcaption></figure>
        figure = doc.create_element('figure')
        figcaption = doc.create_element('figcaption')
        a = doc.create_element('a')
        a['href'] = out[:link]
        a.content = link.text.strip
        img = doc.create_element('img')
        img['src'] = "images/#{out[:filename]}"
        # link.replace img
        figcaption.add_child(a)
        figure.add_child(img)
        figure.add_child(figcaption)
        link.replace(figure)
      end
      out
    }
    html = doc.to_html
    puts html
    return links
  end

puts  extract_links(File.read(File.join('..', 'epubs', '1zig9s', 'out.html')))