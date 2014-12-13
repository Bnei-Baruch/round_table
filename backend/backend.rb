require 'sinatra'
require 'sinatra-websocket'
require 'json'
require 'redis'

require './config/config'

if ENV['RACK_ENV'] == 'test'
    require './config/testing_config'
end

before do
    headers_list = {
        'Access-Control-Allow-Origin' => '*', 
        'Access-Control-Allow-Methods' => 'OPTIONS,GET,POST,PUT',
        'Access-Control-Allow-Headers' => 'Origin,X-Requested-With,Content-Type,Accept'
    }
    headers headers_list
end

set :server, 'thin'
set :sockets, []
set :json_content_type, :js
set :bind, '0.0.0.0'
set :protection, false

redis_config = CONFIG['redis']
$redis = Redis.new(redis_config['host'] => "localhost", :port => redis_config['port'], :db => redis_config['db'])

options '/*' do
    200
end

# Update table
put '/spaces/:space/tables/:id' do
    request.body.rewind
    body = JSON.parse(request.body.read)
    body['timestamp'] = $redis.time[0]
    $redis.set("table_#{params[:space]}_#{params[:id]}", JSON.generate(body))
end

# Get free table
get '/spaces/:space/tables/:language/free' do
    table_id = get_free_table_id(params[:space], params[:language])
    if table_id.nil?
      table_id = ""
    end

    redirect get_hangouts_url(table_id, params[:space], params[:language])
end

$sockets = Hash.new { |sockets, space| sockets[space] = []; }
$master_endpoint_ids = { }

# Websocket
get '/socket' do
  if !request.websocket?
    status 400
    { }.to_json
  else
    request.websocket do |ws|
      ws.onmessage do |msg|
        message = JSON.parse(msg)

        $sockets[message['space']] << ws

        case message['action']
        when 'registerMaster'
            $master_endpoint_ids[message['space']] = message['endpointId']
            viewer_response = get_viewer_response(message['space'])
            EM.next_tick { $sockets[message['space']].each{|s| s.send(viewer_response) } }
        when 'registerViewer'
            viewer_response = get_viewer_response(message['space'])
            unless viewer_response.nil?
                ws.send(viewer_response)
            end
        end
      end
      ws.onclose do
        sockets = $sockets.values.select { |values| values.include? ws }
        sockets.delete(ws)
        warn("Websocket closed")
      end
    end
  end
end

def get_viewer_response(space)
    if $master_endpoint_ids.include? space
        {
            :action => 'assignMasterEndpoint',
            :endpointId => $master_endpoint_ids[space]
        }.to_json
    else
        nil
    end
end

$table_config = CONFIG['table']

def get_hangouts_url(table_id, space, language)
    app_data = { :space => space, :language => language }.to_json
    escaped = URI.escape(app_data)
    "https://plus.google.com/hangouts/_/#{table_id}?gid=#{CONFIG['hangout_app_gid']}&gd=#{escaped}"
end

def get_space_tables(space, language, time_now)
    keys = $redis.keys("table_#{space}_*" )

    live_tables = []
    $redis.mget(*keys).each do |one_table|
        one_table = JSON.parse(one_table)
        if one_table['timestamp'] + $table_config['time_to_live'] < time_now
            table_id = "table_#{one_table['space']}_#{one_table['id']}"
            $redis.del(table_id)
        else
            if is_table_live(one_table, time_now) and (language.nil? or language == one_table['lang'])
                one_table['hangouts_url'] = get_hangouts_url(one_table['id'],
                                                             one_table['space'],
                                                             one_table['lang'])
                live_tables << one_table
            end
        end
    end if not keys.empty?
    live_tables
end

def get_free_table_id(space, language)
    time_now = $redis.time[0]
    live_tables = get_space_tables(space, language, time_now)
    table = choose_table(live_tables, time_now)
    return table['id'] if table
    nil
end

def choose_table(tables, time_now)
    small_tables = tables.select do |one_table|
        one_table['participants'].size < $table_config['min_participants_number']
    end
    return small_tables.max_by { |table| table['participants'].size } if !small_tables.empty?
    not_full_tables = tables.select do |one_table|
      one_table['participants'].size < $table_config['max_participants_number']
    end
    return not_full_tables.min_by { |table| table['participants'].size } if !not_full_tables.empty?
    return nil
end

def is_table_live(table, time_now)
    table['timestamp'] + $table_config['polling_interval'] > time_now
end

get '/spaces/:space/tables' do
    time_now = $redis.time[0]
    live_tables = get_space_tables(params[:space], nil, time_now)
    JSON.generate(live_tables)
end

get '/spaces/tables' do
    time_now = $redis.time[0]
    live_tables = get_space_tables("*", nil, time_now)
    JSON.generate(live_tables)
end
