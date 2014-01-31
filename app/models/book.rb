class Book
  include Mongoid::Document

  field :reddit_id, type: String
  field :subreddit, type: String
  field :thread_name, type: String
  field :save_name, type: String
  field :done, type: Boolean, default: false
  field :submitted_at, type: DateTime, default: ->{ Time.now }
  field :finished_at, type: DateTime

# reddit data
  field :title, type: String
  field :url, type: String
  field :created_at, type: DateTime
  field :image, type: String
  field :youtube_id, type: String
  field :html, type: String
  field :thumbnail, type: String
  field :nsfw, type: Boolean
  field :is_text, type: Boolean

  belongs_to :users

end