-- Load Luarocks paths
local websocket = require("http.websocket")
local cqueues = require("cqueues")
local http_request = require("http.request")
local cjson = require("cjson")

local cq = cqueues.new()

local function get_node_pid()
	local handle = io.popen("pgrep -f 'node'")
	if not handle then
		return nil
	end
	print("HANDLE: " .. handle:read())
	local pid = handle:read()
	handle:close()
	print(pid)
	return pid
end

local function send_debug_signal(pid)
	local cmd = "kill -USR1 " .. pid
	print(cmd)
	if pid then
		io.popen(cmd)
	end
	print("sent debug command")
end

local function wait_for_debugger_port(timeout)
	return "9229"
	-- local start_time = os.time()
	-- while (os.time() - start_time) < timeout do
	-- local handle = io.popen("ss -tlnp | grep node")
	-- if handle then
	-- 	for line in handle:lines() do
	-- 		local port = line:match("127.0.0.1:(%d+)")
	-- 		if port then
	-- 			handle:close()
	-- 			return tonumber(port)
	-- 		end
	-- 	end
	-- 	handle:close()
	-- end
	-- -- end
	-- return nil
end

local function log_debugger_messages(debugger_url)
	local full_url = (debugger_url .. "json")
	print("FULL URL" .. full_url)
	local headers, stream = assert(http_request.new_from_uri(full_url):go())
	local body = assert(stream:get_body_as_string())
	print(body)
	local targets = cjson.decode(body)
	print(targets)
	local ws_url = targets[1].webSocketDebuggerUrl
	print("WS_URL: " .. ws_url)
	print("Connecting to WebSocket URL:", ws_url)

	cq:wrap(function()
		local connected = false
		local ws, err
		for attempt = 1, 15 do
			ws, err = websocket.new_from_uri(ws_url)
			if ws then
				local ok, err = ws:connect()
				if ok then
					connected = true
					break
				end
			end
			print("Connection attempt " .. attempt .. " failed, retrying...")
			cqueues.sleep(1)
		end
		if not connected then
			error("Failed to connect to debugger at " .. debugger_url)
		end
		print("Connected to WebSocket!")
		local cjson = require("cjson")
		local msg_id = 1
		ws:send(cjson.encode({ id = msg_id, method = "Runtime.enable" }))
		msg_id = msg_id + 1
		ws:send(cjson.encode({ id = msg_id, method = "Debugger.enable" }))
		-- Handle messages...
		while true do
			local message, err = ws:receive()
			if message then
				local messageTable = cjson.decode(message)
				print("Received message: " .. message)
				local method = messageTable.method
				if method == "Runtime.consoleAPICalled" then
					print("Console API Called")
					local params = message.params
					local args = params.args
					local log_message = args[1] and args[1].value or "<no message>"
					local callframe = params.stackTrace.callFrames[1]
					local file_url = callframe.url
					local line = callframe.lineNumber + 1 -- Lua uses 1-based indexing
					local path = file_url:gsub("file://", "")
				end
			elseif err then
				print("WebSocket error: " .. tostring(err))
				break
			end
		end
	end)
	assert(cq:loop())
end

local function get_debugger_url()
	local pid = get_node_pid()
	print("PID: " .. pid)
	if not pid then
		print("No Node.js process found.")
		return nil
	end

	send_debug_signal(pid)

	print("Waiting for debugger to start...")
	local port = wait_for_debugger_port(15)
	if not port then
		print("Debugger port not found.")
		return nil
	end

	return "http://127.0.0.1:" .. port .. "/"
end

-- Start application
-- local debugger_url = get_debugger_url()
-- if debugger_url then
-- 	print("Debugger is available at: " .. debugger_url)
-- 	log_debugger_messages(debugger_url)
-- else
-- 	print("Could not determine Node.js debugger URL.")
-- end
--
local M = {}
function M.start()
	local debugger_url = get_debugger_url()
	if debugger_url then
		print("Debugger is available at: " .. debugger_url)
		log_debugger_messages(debugger_url)
	else
		print("Could not determine Node.js debugger URL.")
	end
end

return M
