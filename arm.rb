tenant_id = ENV['ARM_TENANT_ID']
client_id = ENV['ARM_CLIENT_ID']
secret    = ENV['ARM_SECRET']

puts "Azure ARM. Authenticating with params: ten: #{tenant_id} , cli: #{client_id} , sec: #{secret}"
token_provider = MsRestAzure::ApplicationTokenProvider.new(tenant_id, client_id, secret)
credentials = MsRest::TokenCredentials.new(token_provider)
puts "Got credentials: #{credentials}"
