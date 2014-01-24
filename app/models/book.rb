class Book
  include Mongoid::Document

  field :reddit_id, type: String
  field :subreddit, type: String
  field :thread_name, type: String
  field :save_name, type: String
  field :done, type: Boolean, default: false
  field :submitted_at, type: DateTime, default: ->{ Time.now }
  field :finished_at, type: DateTime

  belongs_to :users

end