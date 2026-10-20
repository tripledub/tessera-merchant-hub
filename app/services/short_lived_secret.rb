# frozen_string_literal: true

# A value that has to travel through a place that stores it (a background job's
# arguments, which Solid Queue keeps in the queue database) without being
# stored in plaintext: encrypted with a key derived from the app secret, bound
# to a purpose so it cannot be replayed elsewhere, and expiring. Decrypting a
# value that is expired, tampered with, or made for another purpose gives nil.
module ShortLivedSecret
  module_function

  def encrypt(value, purpose:, expires_in:)
    encryptor.encrypt_and_sign(value, purpose: purpose, expires_in: expires_in)
  end

  def decrypt(token, purpose:)
    return if token.blank?

    encryptor.decrypt_and_verify(token, purpose: purpose)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def encryptor
    key = Rails.application.key_generator.generate_key("short-lived-secret", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key, serializer: JSON)
  end
  private_class_method :encryptor
end
