def ws_request(url, payload)
  queue = TimeoutQueue.new

  Thread.new do
    EM.run do
      ws = Faye::WebSocket::Client.new(url)

      ws.on :open do |event|
        ws.send(payload.to_json)
      end

      ws.on :message do |event|
        if event.data.include?("jsonrpc")
          queue << JSON.parse(event.data)
          ws.close(3001, "data received")
          EM.stop
        end
      end

      ws.on :close do |event|
        ws = nil
      end
    end
  end

  queue.pop true, 5
rescue ThreadError => ex
  raise RpcTimeout
end

class SubstrateClientSync
  class RpcError < StandardError; end
  class RpcTimeout < StandardError; end

  attr_accessor :spec_name, :spec_version, :metadata

  def initialize(url, spec_name: nil)
    @url = url
    @request_id = 1
    @spec_name = spec_name
    Scale::TypeRegistry.instance.load(spec_name)
  end

  def request(method, params)
    payload = {
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => @request_id
    }

    data = ws_request(@url, payload)
    if data["error"]
      raise RpcError, data["error"]
    else
      data["result"]
    end
  end

  def init_runtime(block_hash: nil, block_id: nil)
    if block_hash.nil? 
      if not block_id.nil?
        block_hash = self.chain_get_block_hash(block_id)
      else
        block_hash = self.chain_get_head
      end
    end

    # set current runtime spec version
    runtime_version = self.state_get_runtime_version(block_hash)
    @spec_version = runtime_version["specVersion"]
    Scale::TypeRegistry.instance.spec_version = @spec_version

    # set current metadata
    @metadata = self.get_metadata(block_hash)
    Scale::TypeRegistry.instance.metadata = @metadata.value
    true
  end

  def invoke(method, *params)
    # params.reject! { |param| param.nil? }
    request(method, params)
  end

  def rpc_method(method_name)
    SubstrateClient.real_method_name(method_name.to_s)
  end

  # ################################################
  # origin rpc methods
  # ################################################
  def method_missing(method, *args)
    rpc_method = SubstrateClient.real_method_name(method)
    invoke rpc_method, *args
  end

  def rpc_methods 
    invoke rpc_method(__method__)
  end

  def chain_get_head
    invoke rpc_method(__method__)
  end

  def chain_get_finalised_head
    invoke rpc_method(__method__)
  end

  def chain_get_header(block_hash = nil)
    invoke rpc_method(__method__), block_hash
  end

  def chain_get_block(block_hash = nil)
    invoke rpc_method(__method__), block_hash
  end

  def chain_get_block_hash(block_id)
    invoke rpc_method(__method__), block_id
  end

  def chain_get_runtime_version(block_hash = nil)
    invoke rpc_method(__method__), block_hash
  end

  def state_get_metadata(block_hash = nil)
    invoke rpc_method(__method__), block_hash
  end

  def state_get_storage(storage_key, block_hash = nil)
    invoke rpc_method(__method__), storage_key, block_hash
  end

  def system_name
    invoke rpc_method(__method__)
  end

  def system_version
    invoke rpc_method(__method__)
  end

  # ################################################
  # custom methods based on origin rpc methods
  # ################################################
  def method_list
    self.rpc_methods["methods"].map(&:underscore)
  end

  def get_block_number(block_hash)
    header = self.chain_get_header(block_hash)
    header["number"].to_i(16)
  end

  def get_metadata(block_hash)
    hex = self.state_get_metadata(block_hash)
    Scale::Types::Metadata.decode(Scale::Bytes.new(hex))
  end

  def get_block(block_hash=nil)
    self.init_runtime(block_hash: block_hash)
    block = self.chain_get_block(block_hash)

    block["block"]["header"]["number"] = block["block"]["header"]["number"].to_i(16)

    block["block"]["extrinsics"].each_with_index do |hex, i|
      scale_bytes = Scale::Bytes.new(hex)
      block["block"]["extrinsics"][i] = Scale::Types::Extrinsic.decode(scale_bytes).to_human
    end

    block['block']['header']["digest"]["logs"].each_with_index do |hex, i|
      scale_bytes = Scale::Bytes.new(hex)
      block['block']['header']["digest"]["logs"][i] = Scale::Types::LogDigest.decode(scale_bytes).to_human
    end

    block
  end

  def get_block_events(block_hash)
    self.init_runtime(block_hash: block_hash)

    storage_key =  "0x26aa394eea5630e07c48ae0c9558cef780d41e5e16056765bc8461851072c9d7"
    events_data = state_get_storage storage_key, block_hash

    scale_bytes = Scale::Bytes.new(events_data)
    Scale::Types.get("Vec<EventRecord>").decode(scale_bytes).to_human
  end

  # Plain: client.get_storage("Sudo", "Key")
  # Plain: client.get_storage("Balances", "TotalIssuance")
  # Map: client.get_storage("System", "Account", ["0xd43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d"])
  # DoubleMap: client.get_storage("ImOnline", "AuthoredBlocks", [2818, "0x749ddc93a65dfec3af27cc7478212cb7d4b0c0357fef35a0163966ab5333b757"])
  def get_storage(module_name, storage_name, params = nil, block_hash = nil)
    self.init_runtime(block_hash: block_hash)

    # find the storage item from metadata
    metadata_modules = metadata.value.value[:metadata][:modules]
    metadata_module = metadata_modules.detect { |mm| mm[:name] == module_name }
    raise "Module '#{module_name}' not exist" unless metadata_module
    storage_item = metadata_module[:storage][:items].detect { |item| item[:name] == storage_name }
    raise "Storage item '#{storage_name}' not exist. \n#{metadata_module.inspect}" unless storage_item

    if storage_item[:type][:Plain]
      return_type = storage_item[:type][:Plain]
    elsif map = storage_item[:type][:Map]
      raise "Storage call of type \"Map\" requires 1 parameter" if params.nil? || params.length != 1

      hasher = map[:hasher]
      return_type = map[:value]
      # TODO: decode to account id if param is address
      # params[0] = decode(params[0]) if map[:key] == "AccountId"
      params[0] = Scale::Types.get(map[:key]).new(params[0]).encode
    elsif map = storage_item[:type][:DoubleMap]
      raise "Storage call of type \"DoubleMapType\" requires 2 parameters" if params.nil? || params.length != 2

      hasher = map[:hasher]
      hasher2 = map[:key2Hasher]
      return_type = map[:value]
      params[0] = Scale::Types.get(map[:key1]).new(params[0]).encode
      params[1] = Scale::Types.get(map[:key2]).new(params[1]).encode
    else
      raise NotImplementedError
    end

    storage_hash = SubstrateClient.generate_storage_hash(
      module_name,
      storage_name,
      params,
      hasher,
      hasher2,
      metadata.value.value[:metadata][:version]
    )

    result = self.state_get_storage(storage_hash, block_hash)
    return unless result
    Scale::Types.get(return_type).decode(Scale::Bytes.new(result))
  end

  # compose_call "Balances", "Transfer", { dest: "0x586cb27c291c813ce74e86a60dad270609abf2fc8bee107e44a80ac00225c409", value: 1_000_000_000_000 }
  def compose_call(module_name, call_name, params, block_hash=nil)
    self.init_runtime(block_hash: block_hash)

    call = metadata.get_module_call(module_name, call_name)

    value = {
      call_index: call[:lookup],
      module_name: module_name,
      call_name: call_name,
      params: []
    }

    params.keys.each_with_index do |call_param_name, i|
      param_value = params[call_param_name]
      value[:params] << {
        name: call_param_name.to_s,
        type: call[:args][i][:type],
        value: param_value
      }
    end

    Scale::Types::Extrinsic.new(value).encode
  end

  class << self
    def generate_storage_hash(module_name, storage_name, params = nil, hasher = nil, hasher2 = nil, metadata_version = nil)
      if metadata_version and metadata_version >= 9
        storage_hash = Crypto.twox128(module_name) + Crypto.twox128(storage_name)

        params&.each_with_index do |param, index|
          if index == 0
            param_hasher = hasher
          elsif index == 1
            param_hasher = hasher2
          else
            raise "Unexpected third parameter for storage call"
          end

          param_key = param.hex_to_bytes
          param_hasher = "Twox128" if param_hasher.nil?
          storage_hash += Crypto.send param_hasher.underscore, param_key
        end

        "0x#{storage_hash}"
      else
        # TODO: add test
        storage_hash = module_name + " " + storage_name

        unless params.nil?
          params = [params] if params.class != ::Array
          params_key = params.join("")
          hasher = "Twox128" if hasher.nil?
          storage_hash += params_key.hex_to_bytes.bytes_to_utf8 
        end

        "0x#{Crypto.send( hasher.underscore, storage_hash )}"
      end
    end

    # chain_unsubscribe_runtime_version
    # => 
    # chain_unsubscribeRuntimeVersion
    def real_method_name(method_name)
      segments = method_name.to_s.split("_")
      if segments.length == 1
        segments[0]
      else
        segments[0] + "_" + segments[1] + segments[2..].map(&:capitalize).join
      end
    end

  end

end
