require "socket"
require "json"
require "./net_string"
require "./rpc_api"

module Supervisor
  class Server

    alias RpcRequest = NamedTuple(name: String, args: Array(String | Int32 | Bool))

    def initialize(process_manager)
      @socket = "tmp/sv.sock"
      @api = RpcApi.new(process_manager)
    end

    def start(on_start : Proc(Void))
      File.delete(@socket) if File.exists? @socket
      UNIXServer.open(@socket) do |server|
        puts "server started on #{@socket}"
        on_start.call
        while client = server.accept?
          spawn handle_client(client)
        end
      end
    end

    private def handle_client(client)
      loop do
        json = NetString.read(client)
        break if ! json
        data = RpcRequest.from_json(json)
        name = data[:name]
        args = data[:args]
        response = @api.handle_call(name, args)
        if response
          client << NetString.build(response)
        end
      end
    rescue e : MalformedNetString
      client.puts "Error: #{e.message}"
    rescue e : JSON::ParseException
      client.puts "Error: invalid json"
    rescue e : Errno
      puts "#{e.class}: #{e.message}"
    ensure
      puts "client disconnected"
      client.close
    end
  end
end
