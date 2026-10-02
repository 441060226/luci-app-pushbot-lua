f = SimpleForm("pushbot")
-- 注意：不要调用 /usr/bin/pushbot/pushbot client
-- 该命令会重写并破坏本 view 模板（pushbot_client.htm），
-- 设备列表改由前端 JS 拉取 /admin/services/pushbot/clients 接口渲染。
f.reset = false
f.submit = false
f:append(Template("pushbot/pushbot_client"))
return f
