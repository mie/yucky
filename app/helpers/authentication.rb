module Authentication

  PBKDF2_ITERATIONS = 200
  SALT_BYTE_SIZE = 24
  HASH_BYTE_SIZE = 24

  HASH_SECTIONS = 4
  SECTION_DELIMITER = ':'
  ITERATIONS_INDEX = 1
  SALT_INDEX = 2
  HASH_INDEX = 3

  def create_hash( password )
    salt = SecureRandom.base64( SALT_BYTE_SIZE )
    pbkdf2 = OpenSSL::PKCS5::pbkdf2_hmac_sha1(
      password,
      salt,
      PBKDF2_ITERATIONS,
      HASH_BYTE_SIZE
    )
    return ["sha1", PBKDF2_ITERATIONS, salt, Base64.encode64( pbkdf2 )].join( SECTION_DELIMITER )
  end

  # Checks if a password is correct given a hash of the correct one.
  # correctHash must be a hash string generated with createHash.
  def validate_password( password, correct_hash )
    params = correct_hash.split( SECTION_DELIMITER )
    return false if params.length != HASH_SECTIONS

    pbkdf2 = Base64.decode64( params[HASH_INDEX] )
    testHash = OpenSSL::PKCS5::pbkdf2_hmac_sha1(
      password,
      params[SALT_INDEX],
      params[ITERATIONS_INDEX].to_i,
      pbkdf2.length
    )

    return pbkdf2 == testHash
  end

end