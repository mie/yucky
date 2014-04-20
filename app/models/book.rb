require 'fileutils'

class Book
  include Mongoid::Document
  include Mongoid::Pagination

  field :reddit_id, type: String
  field :subreddit, type: String
  field :thread_name, type: String
  field :save_name, type: String
  field :status, type: String, default: 'queued'
  field :only_first, type: Boolean, default: false
  field :downloads, type: Integer, default: 0
  field :epub_size, type: Integer, default: 0
  field :mobi_size, type: Integer, default: 0
  field :submitted_at, type: Date, default: ->{ Time.now }
  field :submitted_string, type: String, default: ->{ Time.now.strftime('%Y %m %d') }
  field :postponed_at, type: DateTime
  field :finished_at, type: DateTime

# reddit data
  field :title, type: String
  field :score, type: Integer
  field :author, type: String
  field :url, type: String
  field :num_comments, type: Integer
  field :created_utc, type: DateTime
  field :over_18, type: Boolean
  field :thumbnail, type: String, default: 'images/no_image.png'

# options
  field :only_first, type: Boolean, default: false
  field :with_images, type: Boolean, default: true

  before_destroy :clear

  belongs_to :user

  def link
    "http://www.reddit.com/r/#{self.subreddit}\/comments\/#{self.reddit_id}\/#{self.thread_name}"
  end

  def clear
    dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'epubs', self.reddit_id))
    puts dir
    if Dir.exists?(dir)
      FileUtils.rm_r(dir)
      puts 'deleted'
    end
  end

end