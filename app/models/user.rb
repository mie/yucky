class User

  include Mongoid::Document

  field :email, type: String
  field :name, type: String
  field :token, type: String
  field :password, type: String
  field :google_access, type: Hash, default: {}

  has_many :books

  def add_book(b)
    self.books << b unless self.books.include?(b)
  end

  def del_book(b)
    self.books.delete(b) if self.books.include?(b)
  end

end