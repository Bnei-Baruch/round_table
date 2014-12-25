class RoundTable::API
  # Create auth token
  post '/auth/tokens' do
    body = JSON.parse(request.body.read)
    user_json = redis.get("auth_user_#{body['user']}")

    if user_json.nil?
      response_bad_request
    else
      user = JSON.parse(user_json)

      if BCrypt::Password.new(user['password']) == body['password']
        status 201
        {
          :token => create_auth_token,
          :space => user['space']
        }.to_json
      else
        response_bad_request
      end
    end
  end

  def create_auth_token
    token = SecureRandom.urlsafe_base64
    key = "auth_session_#{token}"
    redis.set(key, true)
    redis.expire(key, config['auth']['session_ttl'])
    token
  end

  def response_bad_request
    auth_error = { :error => "Invalid user name or password" }
    [400, [auth_error.to_json]]
  end

end
