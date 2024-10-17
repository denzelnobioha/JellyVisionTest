require 'sinatra'
require 'json'

def parse_gift(raw)
  parsed = JSON.parse(raw)
  parsed['gift']
end

get '/' do
  "Welcome to the Simpson household"
end

get '/homer' do
  "I hope you brought donuts"
end

post '/homer' do
  gift = parse_gift(request.body.read)
  if gift == 'donut'
    [200, 'Woohoo']
  else
    [400, "D'oh"]
  end
end

###################################
# FIXME: Implement Lisa endpoints #
###################################

get '/lisa' do
  "The baritone sax is the best sax"
end

post '/lisa' do
  request_body = JSON.parse(request.body.read)
  gift = request_body['gift']

  case gift
  when 'book'
    status 200
    "I love it"
  when 'saxaphone'
    status 200
    "I REALLY love it"
  when 'video_game'
    status 400
    "I hate it"
  when 'skateboard'
    status 400
    "I REALLY hate it"
  else
    status 400
    "I don't know how I feel about that"
  end
end
