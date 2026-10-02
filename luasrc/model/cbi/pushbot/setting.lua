

local nt = require "luci.sys".net

local fs=require"nixio.fs"

local e=luci.model.uci.cursor()

local net = require "luci.model.network".init()

local sys = require "luci.sys"

local ifaces = sys.net:devices()



m=Map("pushbot",translate("PushBot"),

translate("「全能推送」，英文名「PushBot」，是一款从服务器推送报警信息和日志到各平台的工具。<br>支持钉钉推送，企业微信推送，PushPlus推送。<br>本插件由tty228/luci-app-serverchan创建，然后七年修改为全能推送自用。<br /><br />如果你在使用中遇到问题，请到这里提交：")

.. [[<a href="https://github.com/zzsj0928/luci-app-pushbot" target="_blank">]]

.. translate("github 项目地址")

.. [[</a>]]

)



-- 修复：OpenWrt 25.12 的 LuCI 中 apply_on_parse 默认 nil，导致点「保存并应用」时

-- Map.parse 只 save 不 commit，随后 unload 丢弃内存变更，配置永远无法落盘。

-- 设为 false 后，parse 阶段会真正执行 uci commit。

m.apply_on_parse = false



m:section(SimpleSection).template  = "pushbot/pushbot_status"



s=m:section(NamedSection,"pushbot","pushbot",translate(""))

s:tab("basic", translate("基本设置"))

s:tab("content", translate("推送内容"))

s:tab("crontab", translate("定时推送"))

s:tab("disturb", translate("免打扰"))

s.addremove = false

s.anonymous = true



--基本设置

a=s:taboption("basic", Flag,"pushbot_enable",translate("启用"))

a.default=0

a.rmempty = true



--精简模式

a = s:taboption("basic", MultiValue, "lite_enable", translate("精简模式"))

a:value("device", translate("精简当前设备列表"))

a:value("nowtime", translate("精简当前时间"))

a:value("content", translate("只推送标题"))

a.widget = "checkbox"

a.default = nil

a.optional = true



--推送平台（多选：可同时推送到多个平台）
a=s:taboption("basic", MultiValue,"pushbot_channels",translate("推送平台（可多选）"))
a.widget = "checkbox"
a.default = nil
a.rmempty = true
a.optional = true
a:value("/usr/bin/pushbot/api/dingding.json",translate("钉钉"))
a:value("/usr/bin/pushbot/api/ent_wechat.json",translate("企业微信机器人"))
a:value("/usr/bin/pushbot/api/ent_wechat_app.json",translate("企业微信应用"))
a:value("/usr/bin/pushbot/api/feishu.json",translate("飞书"))
a:value("/usr/bin/pushbot/api/bark.json",translate("Bark"))
a:value("/usr/bin/pushbot/api/pushplus.json",translate("PushPlus"))
a:value("/usr/bin/pushbot/api/pushdeer.json",translate("PushDeer"))
a:value("/usr/bin/pushbot/api/diy.json",translate("自定义推送"))
a.description = translate("勾选需要接收推送的平台，可多选。<br/>同一条消息会同时推送到所有已勾选的平台，<b>消息格式以列表中第一个平台为准</b>。<br/>勾选后，下方会自动展开该平台对应的配置项。")

-- 平台联动说明：本版本 LuCI 的 MultiValue 渲染为多选下拉，depends 在首次渲染阶段
-- 无法可靠取值（字段会被整块移出 DOM，用户看不到也改不了）。
-- 因此这里改用前端脚本 pushbot_channels.js 读取真实勾选状态，动态显示对应配置行。
-- 用一个隐藏的 DummyValue 承载样式与脚本的注入（不占用任何真实配置项）。
a=s:taboption("basic", DummyValue, "__pb_channels_ui", "")
a.template = "pushbot/pushbot_channels_note"


-- 兼容旧版单选配置（不再显示，仅保留 UCI 值供脚本回退使用）
-- jsonpath 字段已隐藏：只要上方多选勾选了任意平台，pushbot 脚本的 parse_channels()
-- 就只读取 pushbot_channels，旧值不会被使用；保留该 UCI 值是为了旧版本升级用户
-- 在未勾选任何平台时仍能正常推送，故不删除配置项、仅不渲染。
local legacy_json = e:get("pushbot","pushbot","jsonpath")
if legacy_json and legacy_json ~= "" then
	-- 迁移提示：旧单选值若未被多选覆盖，主动提示用户
	local channels_now = e:get("pushbot","pushbot","pushbot_channels")
	if not channels_now or channels_now == "" then
		m.description = (m.description or "") .. translate("<br/><span style='color:#e67e22'>检测到旧版推送模式配置，建议在上方「推送平台（可多选）」中重新勾选。</span>")
	end
end

------------------------------------------------------------------------
-- 一、钉钉
------------------------------------------------------------------------
a=s:taboption("basic", Value,"dd_webhook",translate('钉钉 · Webhook'), translate("钉钉机器人 Webhook").."，只输入access_token=后面的即可<br>调用代码获取<a href='https://developers.dingtalk.com/document/robots/custom-robot-access' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true

------------------------------------------------------------------------
-- 二、企业微信机器人
------------------------------------------------------------------------
a=s:taboption("basic", Value, "we_webhook", translate("企业微信机器人 · Webhook"),translate("企业微信机器人 Webhook").."，只输入key=后面的即可<br>调用代码获取<a href='https://work.weixin.qq.com/api/doc/90000/90136/91770' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true

------------------------------------------------------------------------
-- 三、企业微信应用
------------------------------------------------------------------------
a=s:taboption("basic", Value, "we_corpid", translate("企业微信应用 · 企业ID"), translate("企业微信应用推送 - 企业ID").."<br>登录企业微信管理后台 → 我的企业 → 企业信息 中获取<br>调用文档<a href='https://developer.work.weixin.qq.com/document/path/91039' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true

a=s:taboption("basic", Value, "we_corpsecret", translate("企业微信应用 · 应用密钥"), translate("企业微信应用推送 - 应用 Secret").."<br>应用管理 → 自建应用 → 查看 Secret<br><br>")
a.rmempty = false
a.optional = true

a=s:taboption("basic", Value, "we_agentid", translate("企业微信应用 · 应用ID"), translate("企业微信应用推送 - 应用 AgentId").."<br>应用管理 → 自建应用 页面顶部的 AgentId<br><br>")
a.rmempty = false
a.optional = true

a=s:taboption("basic", Value, "we_touser", translate("企业微信应用 · 接收成员"), translate("企业微信应用推送 - 接收成员").."<br>填写成员账号（UserID），多个用竖线分隔，如：<code>user1|user2</code><br>填 <code>@all</code> 表示全员推送<br><br>")
a.rmempty = false
a.optional = true
a.default = "@all"

------------------------------------------------------------------------
-- 四、飞书
------------------------------------------------------------------------
a=s:taboption("basic", Value,"fs_webhook",translate('飞书 · WebHook'), translate("飞书 WebHook").."<br>调用代码获取<a href='https://www.feishu.cn/hc/zh-CN/articles/360024984973' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true

------------------------------------------------------------------------
-- 五、Bark
------------------------------------------------------------------------
a=s:taboption("basic", Value,"bark_token",translate('Bark · Token'), translate("Bark Token").."<br>调用代码获取<a href='https://github.com/Finb/Bark' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true

a=s:taboption("basic", Flag,"bark_srv_enable",translate("Bark · 自建服务器"))
a.default=0
a.rmempty = true

a=s:taboption("basic", Value,"bark_srv",translate('Bark · 服务器地址'), translate("Bark 自建服务器地址").."<br>如https://your.domain:port<br>具体自建服务器设定参见：<a href='https://github.com/Finb/Bark' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true
a:depends("bark_srv_enable","1")

a=s:taboption("basic", Value,"bark_sound",translate('Bark · 通知声音'), translate("Bark 通知声音").."<br>如silence.caf<br>具体设定参见：<a href='https://github.com/Finb/Bark/tree/master/Sounds' target='_blank'>点击这里</a><br><br>")
a.rmempty = true
a.default = "silence.caf"

a=s:taboption("basic", Flag,"bark_icon_enable",translate("Bark · 通知图标"))
a.default=0
a.rmempty = true

a=s:taboption("basic", Value,"bark_icon",translate('Bark · 图标地址'), translate("Bark 通知图标").."(仅 iOS15 或以上支持)<br>如http://day.app/assets/images/avatar.jpg<br>具体设定参见：<a href='https://github.com/Finb/Bark#%E5%85%B6%E4%BB%96%E5%8F%82%E6%95%B0' target='_blank'>点击这里</a><br><br>")
a.rmempty = true
a.default = "http://day.app/assets/images/avatar.jpg"
a:depends("bark_icon_enable","1")

a=s:taboption("basic", ListValue,"bark_level",translate('Bark · 时效性通知'), translate("Bark 时效性通知").."<br>active：默认，系统会立即亮屏显示通知。<br/>timeSensitive：时效性通知，可在专注状态下显示通知。<br/>passive：仅添加到通知列表，不会亮屏提醒。<br><br>")
a.rmempty = true
a.default = "active"
a:value("active", translate("active（默认）"))
a:value("timeSensitive", translate("timeSensitive（时效性）"))
a:value("passive", translate("passive（静默）"))

------------------------------------------------------------------------
-- 六、PushPlus
------------------------------------------------------------------------
a=s:taboption("basic", Value,"pp_token",translate('PushPlus · Token'), translate("PushPlus Token").."<br>调用代码获取<a href='http://pushplus.plus/doc/' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true

a=s:taboption("basic", ListValue,"pp_channel",translate('PushPlus · 渠道'))
a.rmempty = true
a:value("wechat",translate("wechat：微信公众号"))
a:value("cp",translate("cp：企业微信应用"))
a:value("webhook",translate("webhook：第三方webhook"))
a:value("sms",translate("sms：短信"))
a:value("mail",translate("mail：邮箱"))
a.description = translate("webhook：企业微信、钉钉、飞书、server酱<br>sms短信/mail邮箱：PushPlus暂未开放<br>具体channel设定参见：<a href='http://pushplus.plus/doc/extend/webhook.html' target='_blank'>点击这里</a>")

a=s:taboption("basic", Value,"pp_webhook",translate('PushPlus · 自定义Webhook'), translate("PushPlus 自定义Webhook").."<br>第三方webhook或企业微信调用<br>具体自定义Webhook设定参见：<a href='http://pushplus.plus/doc/extend/webhook.html' target='_blank'>点击这里</a><br><br>")
a.rmempty = true
a:depends("pp_channel","cp")
a:depends("pp_channel","webhook")

a=s:taboption("basic", Flag,"pp_topic_enable",translate("PushPlus · 一对多推送"))
a.default=0
a.rmempty = true
a:depends("pp_channel","wechat")

a=s:taboption("basic", Value,"pp_topic",translate('PushPlus · 群组编码'), translate("PushPlus 群组编码").."<br>一对多推送时指定的群组编码<br>具体群组编码Topic设定参见：<a href='http://www.pushplus.plus/push2.html' target='_blank'>点击这里</a><br><br>")
a.rmempty = true
a:depends("pp_topic_enable","1")

------------------------------------------------------------------------
-- 七、PushDeer
------------------------------------------------------------------------
a=s:taboption("basic", Value,"pushdeer_key",translate('PushDeer · Key'), translate("PushDeer Key").."<br>调用代码获取<a href='http://www.pushdeer.com/' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true

a=s:taboption("basic", Flag,"pushdeer_srv_enable",translate("PushDeer · 自建服务器"))
a.default=0
a.rmempty = true

a=s:taboption("basic", Value,"pushdeer_srv",translate('PushDeer · 服务器地址'), translate("PushDeer 自建服务器地址").."<br>如https://your.domain:port<br>具体自建服务器设定参见：<a href='http://www.pushdeer.com/selfhosted.html' target='_blank'>点击这里</a><br><br>")
a.rmempty = false
a.optional = true
a:depends("pushdeer_srv_enable","1")

------------------------------------------------------------------------
-- 八、自定义推送
------------------------------------------------------------------------
a=s:taboption("basic", TextValue, "diy_json", translate("自定义推送 · JSON 配置"))
a.optional = false
a.rows = 20
a.wrap = "soft"
a.cfgvalue = function(self, section)
    return fs.readfile("/usr/bin/pushbot/api/diy.json")
end
a.write = function(self, section, value)
    fs.writefile("/usr/bin/pushbot/api/diy.json", value:gsub("\r\n", "\n"))
end
a.description = translate("自定义推送平台的 JSON 配置。上方「推送平台」勾选「自定义推送」后生效。")

------------------------------------------------------------------------
-- 九、通用（发送测试 / 设备名称 / 检测间隔 等）
------------------------------------------------------------------------
a=s:taboption("basic", Button,"__add",translate("发送测试"))
a.inputtitle=translate("发送")
a.inputstyle = "apply"
function a.write(self, section)
	luci.sys.call("cbi.apply")
	luci.sys.call("/usr/bin/pushbot/pushbot test &")
end

a=s:taboption("basic", Value,"device_name",translate('本设备名称'))
a.rmempty = true
a.description = translate("在推送信息标题中会标识本设备名称，用于区分推送信息的来源设备")

a=s:taboption("basic", Value,"sleeptime",translate('检测时间间隔'))
a.rmempty = true
a.optional = false
a.default = "60"
a.datatype = "and(uinteger,min(10))"
a.description = translate("越短的时间时间响应越及时，但会占用更多的系统资源")

a=s:taboption("basic", ListValue,"oui_data",translate("MAC设备信息数据库"))
a.rmempty = true
a.default=""
a:value("",translate("关闭"))
a:value("1",translate("简化版"))
a:value("2",translate("完整版"))
a:value("3",translate("网络查询"))
a.description = translate("需下载 4.36m 原始数据，处理后完整版约 1.2M，简化版约 250kb <br/>若无梯子，请勿使用网络查询")

a=s:taboption("basic", Flag,"oui_dir",translate("下载到内存"))
a.rmempty = true
a:depends("oui_data","1")
a:depends("oui_data","2")
a.description = translate("懒得做自动更新了，下载到内存中，重启会重新下载 <br/>若无梯子，还是下到机身吧")

a=s:taboption("basic", Flag,"reset_regularly",translate("每天零点重置流量数据"))
a.rmempty = true

a=s:taboption("basic", Flag,"debuglevel",translate("开启日志"))
a.rmempty = true

-- 设备别名已隐藏：设备命名统一由「设备管理」页的「备注」维护（nlbwmon notes），
-- 备注在 pushbot 脚本 getname() 中是最高优先级名称来源，此处的 device_aliases
-- 仅作为备注缺失时的兜底。为避免两处配置冲突/困惑，不再在此页渲染。
-- UCI 值保留不动，脚本逻辑亦不变，老用户已有配置继续有效。


--设备状态

a=s:taboption("content", ListValue,"pushbot_ipv4",translate("IPv4 变更通知"))

a.rmempty = true

a.default=""

a:value("",translate("关闭"))

a:value("1",translate("通过接口获取"))

a:value("2",translate("通过URL获取"))



a = s:taboption("content", ListValue, "ipv4_interface", translate("接口名称"))

a.rmempty = true

a:depends({pushbot_ipv4="1"})

for _, iface in ipairs(ifaces) do

	if not (iface == "lo" or iface:match("^ifb.*")) then

		local nets = net:get_interface(iface)

		nets = nets and nets:get_networks() or {}

		for k, v in pairs(nets) do

			nets[k] = nets[k].sid

		end

		nets = table.concat(nets, ",")

		a:value(iface, ((#nets > 0) and "%s (%s)" % {iface, nets} or iface))

	end

end

a.description = translate("<br/>一般选择 wan 接口，多拨环境请自行选择")



a=s:taboption("content", TextValue, "ipv4_list", translate("IPv4 API列表"))

a.optional = false

a.rows = 8

a.wrap = "soft"

a.cfgvalue = function(self, section)

    return fs.readfile("/usr/bin/pushbot/api/ipv4.list")

end

a.write = function(self, section, value)

    fs.writefile("/usr/bin/pushbot/api/ipv4.list", value:gsub("\r\n", "\n"))

end

a.description = translate("<br/>会因服务器稳定性、连接频繁等原因导致获取失败<br/>如接口可以正常获取 IP，不推荐使用<br/>从以上列表中随机地址访问")

a:depends({pushbot_ipv4="2"})



a=s:taboption("content", ListValue,"pushbot_ipv6",translate("IPv6 变更通知"))

a.rmempty = true

a.default="disable"

a:value("0",translate("关闭"))

a:value("1",translate("通过接口获取"))

a:value("2",translate("通过URL获取"))



a = s:taboption("content", ListValue, "ipv6_interface", translate("接口名称"))

a.rmempty = true

a:depends({pushbot_ipv6="1"})

for _, iface in ipairs(ifaces) do

	if not (iface == "lo" or iface:match("^ifb.*")) then

		local nets = net:get_interface(iface)

		nets = nets and nets:get_networks() or {}

		for k, v in pairs(nets) do

			nets[k] = nets[k].sid

		end

		nets = table.concat(nets, ",")

		a:value(iface, ((#nets > 0) and "%s (%s)" % {iface, nets} or iface))

	end

end

a.description = translate("<br/>一般选择 wan 接口，多拨环境请自行选择")



a=s:taboption("content", TextValue, "ipv6_list", translate("IPv6 API列表"))

a.optional = false

a.rows = 8

a.wrap = "soft"

a.cfgvalue = function(self, section)

    return fs.readfile("/usr/bin/pushbot/api/ipv6.list")

end

a.write = function(self, section, value)

    fs.writefile("/usr/bin/pushbot/api/ipv6.list", value:gsub("\r\n", "\n"))

end

a.description = translate("<br/>会因服务器稳定性、连接频繁等原因导致获取失败<br/>如接口可以正常获取 IP，不推荐使用<br/>从以上列表中随机地址访问")

a:depends({pushbot_ipv6="2"})



a=s:taboption("content", Flag,"pushbot_up",translate("设备上线通知"))

a.default=1

a.rmempty = true



a=s:taboption("content", Flag,"pushbot_down",translate("设备下线通知"))

a.default=1

a.rmempty = true



a=s:taboption("content", Flag,"cpuload_enable",translate("CPU 负载报警"))

a.default=1

a.rmempty = true



a= s:taboption("content", Value, "cpuload", "负载报警阈值")

a.default = 2

a.rmempty = true

a:depends({cpuload_enable="1"})



a=s:taboption("content", Flag,"temperature_enable",translate("CPU 温度报警"))

a.default=1

a.rmempty = true

a.description = translate("请确认设备可以获取温度，如需修改命令，请移步高级设置")



a= s:taboption("content", Value, "temperature", "温度报警阈值")

a.rmempty = true

a.default = "80"

a.datatype="uinteger"

a:depends({temperature_enable="1"})

a.description = translate("<br/>设备报警只会在连续五分钟超过设定值时才会推送<br/>而且一个小时内不会再提醒第二次")



a=s:taboption("content", Flag,"client_usage",translate("设备异常流量"))

a.default=0

a.rmempty = true



a= s:taboption("content", Value, "client_usage_max", "每分钟流量限制")

a.default = "10M"

a.rmempty = true

a:depends({client_usage="1"})

a.description = translate("设备异常流量警报（byte），你可以追加 K 或者 M")



a=s:taboption("content", Flag,"client_usage_disturb",translate("异常流量免打扰"))

a.default=1

a.rmempty = true

a:depends({client_usage="1"})



a = s:taboption("content", DynamicList, "client_usage_whitelist", translate("异常流量关注列表"))

nt.mac_hints(function(mac, name) a:value(mac, "%s (%s)" %{ mac, name }) end)

a.rmempty = true

a:depends({client_usage_disturb="1"})

a.description = translate("请输入设备 MAC")



--LoginNoti

a=s:taboption("content", Flag,"web_logged",translate("Web 登录提醒"))

a.default=0

a.rmempty = true



a=s:taboption("content", Flag,"ssh_logged",translate("SSH 登录提醒"))

a.default=0

a.rmempty = true



a=s:taboption("content", Flag,"web_login_failed",translate("Web 错误尝试提醒"))

a.default=0

a.rmempty = true



a=s:taboption("content", Flag,"ssh_login_failed",translate("SSH 错误尝试提醒"))

a.default=0

a.rmempty = true



a= s:taboption("content", Value, "login_max_num", "错误尝试次数")

a.default = "3"

a.datatype="and(uinteger,min(1))"

a:depends("web_login_failed","1")

a:depends("ssh_login_failed","1")

a.description = translate("超过次数后推送提醒")



a=s:taboption("content", Flag,"web_login_black",translate("自动拉黑"))

a.default=0

a.rmempty = true

a:depends("web_login_failed","1")

a:depends("ssh_login_failed","1")

a.description = translate("直到重启前都不会重置次数，请先添加白名单")



a= s:taboption("content", Value, "ip_black_timeout", "拉黑时间(秒)")

a.default = "86400"

a.datatype="and(uinteger,min(0))"

a:depends("web_login_black","1")

a.description = translate("0 为永久拉黑，慎用<br>如不幸误操作，请更改设备 IP 进入 LUCI 界面清空规则")



a=s:taboption("content", DynamicList, "ip_white_list", translate("白名单 IP 列表"))

a.datatype = "ipaddr"

a.rmempty = true

luci.ip.neighbors({family = 4}, function(entry)

	if entry.reachable then

		a:value(entry.dest:string())

	end

end)

a:depends("web_logged","1")

a:depends("ssh_logged","1")

a:depends("web_login_failed","1")

a:depends("ssh_login_failed","1")

a.description = translate("忽略白名单登陆提醒和拉黑操作，暂不支持掩码位表示")



a=s:taboption("content", TextValue, "ip_black_list", translate("IP 黑名单列表"))

a.optional = false

a.rows = 8

a.wrap = "soft"

a.cfgvalue = function(self, section)

    return fs.readfile("/usr/bin/pushbot/api/ip_blacklist")

end

a.write = function(self, section, value)

    fs.writefile("/usr/bin/pushbot/api/ip_blacklist", value:gsub("\r\n", "\n"))

end

a:depends("web_login_black","1")



--定时推送

a=s:taboption("crontab", ListValue,"crontab",translate("定时任务设定"))

a.rmempty = true

a.default=""

a:value("",translate("关闭"))

a:value("1",translate("定时发送"))

a:value("2",translate("间隔发送"))



a=s:taboption("crontab", ListValue,"regular_time",translate("发送时间"))

a.rmempty = true

for t=0,23 do

a:value(t,translate("每天"..t.."点"))

end

a.default=8

a.datatype=uinteger

--a:depends("crontab","1")  -- 已在补丁中移除(crontab depends bug)



a=s:taboption("crontab", ListValue,"regular_time_2",translate("发送时间"))

a.rmempty = true

a:value("",translate("关闭"))

for t=0,23 do

a:value(t,translate("每天"..t.."点"))

end

a.default="关闭"

a.datatype=uinteger

--a:depends("crontab","1")  -- 已在补丁中移除(crontab depends bug)



a=s:taboption("crontab", ListValue,"regular_time_3",translate("发送时间"))

a.rmempty = true



a:value("",translate("关闭"))

for t=0,23 do

a:value(t,translate("每天"..t.."点"))

end

a.default="关闭"

a.datatype=uinteger

--a:depends("crontab","1")  -- 已在补丁中移除(crontab depends bug)



a=s:taboption("crontab", ListValue,"interval_time",translate("发送间隔"))

a.rmempty = true

for t=1,23 do

a:value(t,translate(t.."小时"))

end

a.default=6

a.datatype=uinteger

--a:depends("crontab","2")  -- 已在补丁中移除(crontab depends bug)

a.description = translate("<br/>从 00:00 开始，每 * 小时发送一次")



a= s:taboption("crontab", Value, "send_title", translate("推送标题"))

-- 移除 depends：LuCI 对 ListValue 多值 depends 判定有 bug，会导致字段永久隐藏

a.placeholder = "OpenWrt By tty228 路由状态："

a.description = translate("<br/>使用特殊符号可能会造成发送失败")



a=s:taboption("crontab", Flag,"router_status",translate("系统运行情况"))

a.default=1

--a:depends("crontab","1")  -- 已在补丁中移除(crontab depends bug)

--a:depends("crontab","2")  -- 已在补丁中移除(crontab depends bug)



a=s:taboption("crontab", Flag,"router_temp",translate("设备温度"))

a.default=1

--a:depends("crontab","1")  -- 已在补丁中移除(crontab depends bug)

--a:depends("crontab","2")  -- 已在补丁中移除(crontab depends bug)



a=s:taboption("crontab", Flag,"router_wan",translate("WAN信息"))

a.default=1

--a:depends("crontab","1")  -- 已在补丁中移除(crontab depends bug)

--a:depends("crontab","2")  -- 已在补丁中移除(crontab depends bug)



a=s:taboption("crontab", Flag,"client_list",translate("客户端列表"))

a.default=1

--a:depends("crontab","1")  -- 已在补丁中移除(crontab depends bug)

--a:depends("crontab","2")  -- 已在补丁中移除(crontab depends bug)



a=s:taboption("crontab", Value,"client_list_max",translate("客户端列表最多显示台数"))

a.rmempty = true

a.optional = true

a.default = "20"

a.datatype = "and(uinteger,min(1))"

a.description = translate("<br/>企业微信 markdown 内容上限 4096 字节，设备过多会导致整条推送失败。默认 20 台，超出部分只显示汇总提示")



a=s:taboption("crontab", Value,"google_check_timeout",translate("全球互联检测超时时间"))

a.rmempty = true

a.optional = false

a.default = "10"

a.datatype = "and(uinteger,min(3))"

a.description = translate("过短的时间可能导致检测不准确")



e=s:taboption("crontab", Button,"_add",translate("手动发送"))

e.inputtitle=translate("发送")

e:depends("crontab","1")

e:depends("crontab","2")

e.inputstyle = "apply"

function e.write(self, section)

luci.sys.call("cbi.apply")

        luci.sys.call("/usr/bin/pushbot/pushbot send &")

end



--免打扰

a=s:taboption("disturb", ListValue,"pushbot_sheep",translate("免打扰时段设置"),translate("在指定整点时间段内，暂停推送消息<br/>免打扰时间中，定时推送也会被阻止。"))

a.rmempty = true



a:value("",translate("关闭"))

a:value("1",translate("模式一：脚本挂起"))

a:value("2",translate("模式二：静默模式"))

a.description = translate("模式一停止一切检测，包括无人值守。")

a=s:taboption("disturb", ListValue,"starttime",translate("免打扰开始时间"))

a.rmempty = true



for t=0,23 do

a:value(t,translate("每天"..t.."点"))

end

a.default=0

a.datatype=uinteger

a:depends({pushbot_sheep="1"})

a:depends({pushbot_sheep="2"})

a=s:taboption("disturb", ListValue,"endtime",translate("免打扰结束时间"))

a.rmempty = true



for t=0,23 do

a:value(t,translate("每天"..t.."点"))

end

a.default=8

a.datatype=uinteger

a:depends({pushbot_sheep="1"})

a:depends({pushbot_sheep="2"})



a=s:taboption("disturb", ListValue,"macmechanism",translate("MAC过滤"))

a:value("",translate("disable"))

a:value("allow",translate("忽略列表内设备"))

a:value("block",translate("仅通知列表内设备"))

a:value("interface",translate("仅通知此接口设备"))

a.rmempty = true





a = s:taboption("disturb", DynamicList, "pushbot_whitelist", translate("忽略列表"))

nt.mac_hints(function(mac, name) a :value(mac, "%s (%s)" %{ mac, name }) end)

a.rmempty = true

a:depends({macmechanism="allow"})

a.description = translate("AA:AA:AA:AA:AA:AA\\|BB:BB:BB:BB:BB:B 可以将多个 MAC 视为同一用户<br/>任一设备在线后不再推送，设备全部离线时才会推送，避免双 wifi 频繁推送")



a = s:taboption("disturb", DynamicList, "pushbot_blacklist", translate("关注列表"))

nt.mac_hints(function(mac, name) a:value(mac, "%s (%s)" %{ mac, name }) end)

a.rmempty = true

a:depends({macmechanism="block"})

a.description = translate("AA:AA:AA:AA:AA:AA\\|BB:BB:BB:BB:BB:B 可以将多个 MAC 视为同一用户<br/>任一设备在线后不再推送，设备全部离线时才会推送，避免双 wifi 频繁推送")



a = s:taboption("disturb", ListValue, "pushbot_interface", translate("接口名称"))

a:depends({macmechanism="interface"})

a.rmempty = true



for _, iface in ipairs(ifaces) do

	if not (iface == "lo" or iface:match("^ifb.*")) then

		local nets = net:get_interface(iface)

		nets = nets and nets:get_networks() or {}

		for k, v in pairs(nets) do

			nets[k] = nets[k].sid

		end

		nets = table.concat(nets, ",")

		a:value(iface, ((#nets > 0) and "%s (%s)" % {iface, nets} or iface))

	end

end



a=s:taboption("disturb", ListValue,"macmechanism2",translate("MAC过滤2"))

a:value("",translate("disable"))

a:value("MAC_online",translate("列表内任意设备在线时免打扰"))

a:value("MAC_offline",translate("列表内设备都离线后免打扰"))

a.rmempty = true



a = s:taboption("disturb", DynamicList, "MAC_online_list", translate("在线免打扰列表"))

nt.mac_hints(function(mac, name) a:value(mac, "%s (%s)" %{ mac, name }) end)

a.rmempty = true

a:depends({macmechanism2="MAC_online"})



a = s:taboption("disturb", DynamicList, "MAC_offline_list", translate("任意离线免打扰列表"))

nt.mac_hints(function(mac, name) a:value(mac, "%s (%s)" %{ mac, name }) end)

a.rmempty = true

a:depends({macmechanism2="MAC_offline"})



return m

