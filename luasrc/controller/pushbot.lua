module("luci.controller.pushbot",package.seeall)

function index()
	if not nixio.fs.access("/etc/config/pushbot") then
		return
	end

	entry({"admin", "services", "pushbot"}, alias("admin", "services", "pushbot", "setting"),_("全能推送"), 30).dependent = true
	entry({"admin", "services", "pushbot", "setting"}, cbi("pushbot/setting"),_("配置"), 40).leaf = true
	entry({"admin", "services", "pushbot", "advanced"}, cbi("pushbot/advanced"),_("高级设置"), 50).leaf = true
	entry({"admin", "services", "pushbot", "client"}, form("pushbot/client"), "在线设备", 80)
	entry({"admin", "services", "pushbot", "log"}, form("pushbot/log"),_("日志"), 99).leaf = true
	entry({"admin", "services", "pushbot", "get_log"}, call("get_log")).leaf = true
	entry({"admin", "services", "pushbot", "clear_log"}, call("clear_log")).leaf = true
	entry({"admin", "services", "pushbot", "status"}, call("act_status")).leaf = true
	-- 在线设备数据接口（新增）
	entry({"admin", "services", "pushbot", "clients"}, call("get_clients")).leaf = true
	-- 设备备注写入接口（新增）
	entry({"admin", "services", "pushbot", "setnote"}, call("set_note")).leaf = true
end

function act_status()
	local e={}
	e.running=luci.sys.call("busybox ps|grep -v grep|grep -c pushbot >/dev/null")==0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

function get_log()
	luci.http.write(luci.sys.exec(
		"[ -f '/tmp/pushbot/pushbot.log' ] && cat /tmp/pushbot/pushbot.log"))
end

function clear_log()
	luci.sys.call("echo '' > /tmp/pushbot/pushbot.log")
end

-- 在线设备列表：调用 pushbot-clients 后端，输出 JSON
-- 参数: scan=1 主动扫描; w=实时采样秒数(0=不采样)
function get_clients()
	local scan = luci.http.formvalue("scan")
	local w = luci.http.formvalue("w")

	local args = "list"
	if scan == "1" then args = args .. " --scan" end
	if w and w:match("^%d+$") then
		args = args .. " -w " .. w
	elseif w == "0" then
		args = args .. " --no-live"
	end

	local out = luci.sys.exec("/usr/libexec/pushbot-clients " .. args .. " 2>/dev/null")

	luci.http.prepare_content("application/json")
	if not out or out == "" then
		luci.http.write('{"ts":0,"count":0,"error":"empty","clients":[]}')
	else
		luci.http.write(out)
	end
end

-- 设备备注写入：mac=MAC 地址; note=备注文本（空则删除备注）
-- 备注统一存于 /etc/nlbwmon/notes.json，与 nlbwmon 带宽监控共享。
function set_note()
	local mac  = luci.http.formvalue("mac")
	local note = luci.http.formvalue("note")
	local ok, msg = false, ""

	luci.http.prepare_content("application/json")

	if not mac or not mac:match("^[0-9A-Fa-f:%-]+$") then
		luci.http.write_json({ ok = false, error = "invalid mac" })
		return
	end

	if note == nil then note = "" end
	-- 归一化：大写、冒号分隔
	mac = mac:upper():gsub("%-", ":")

	if note == "" then
		local out = luci.sys.exec("/usr/libexec/nlbwmon-notes del '" .. mac .. "' 2>&1")
		ok = out:match('"ok"') ~= nil
		msg = "deleted"
	else
		-- 去除换行，防止破坏 JSON 存储
		note = note:gsub("[\r\n]+", " ")
		local out = luci.sys.exec("/usr/libexec/nlbwmon-notes set '" .. mac .. "' " .. luci.util.shellquote(note) .. " 2>&1")
		ok = out:match('"ok"') ~= nil
		msg = note
	end

	luci.http.write_json({ ok = ok, mac = mac, note = msg })
end
