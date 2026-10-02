'use strict';
/*
 * pushbot 配置页「推送平台」联动脚本
 * ------------------------------------------------------------------
 * 背景：本版本 LuCI 的 CBI.MultiValue 实际渲染为 ui.Dropdown(multiple)，
 * 其 formvalue() 在首次渲染阶段尚未绑定，导致 `a:depends("pushbot_channels", ...)`
 * 无法可靠判定 → 被 depends 关联的凭据字段会整块从 DOM 中消失（而非隐藏），
 * 用户永远看不到、也改不了对应平台的配置。
 *
 * 方案：不用 depends，改为在本脚本中直接读取复选框的真实勾选状态，
 * 按「平台 → 所属字段」映射动态显示/隐藏对应配置行。可靠且即时。
 */
(function () {
	// 平台 json 路径 → 该平台需要显示的字段名列表
	var MAP = {
		'/usr/bin/pushbot/api/dingding.json':       ['dd_webhook'],
		'/usr/bin/pushbot/api/ent_wechat.json':     ['we_webhook'],
		'/usr/bin/pushbot/api/ent_wechat_app.json': ['we_corpid', 'we_corpsecret', 'we_agentid', 'we_touser'],
		'/usr/bin/pushbot/api/feishu.json':         ['fs_webhook'],
		'/usr/bin/pushbot/api/bark.json':           ['bark_token', 'bark_srv_enable', 'bark_sound', 'bark_icon_enable', 'bark_level'],
		'/usr/bin/pushbot/api/pushplus.json':       ['pp_token', 'pp_channel', 'pp_topic_enable'],
		'/usr/bin/pushbot/api/pushdeer.json':       ['pushdeer_key', 'pushdeer_srv_enable'],
		'/usr/bin/pushbot/api/diy.json':            ['diy_json']
	};

	// 平台名（用于分组小标题）
	var LABEL = {
		'/usr/bin/pushbot/api/dingding.json':       '钉钉',
		'/usr/bin/pushbot/api/ent_wechat.json':     '企业微信机器人',
		'/usr/bin/pushbot/api/ent_wechat_app.json': '企业微信应用',
		'/usr/bin/pushbot/api/feishu.json':         '飞书',
		'/usr/bin/pushbot/api/bark.json':           'Bark',
		'/usr/bin/pushbot/api/pushplus.json':       'PushPlus',
		'/usr/bin/pushbot/api/pushdeer.json':       'PushDeer',
		'/usr/bin/pushbot/api/diy.json':            '自定义推送'
	};

	var CONFIG = 'pushbot', SECTION = 'pushbot', OPT = 'pushbot_channels';
	var rowId = function (name) { return 'cbi-' + CONFIG + '-' + SECTION + '-' + name; };

	// 读取当前勾选的平台集合
	function selected() {
		var wrap = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.' + OPT);
		var out = [];
		if (!wrap) return out;
		var boxes = wrap.querySelectorAll('input[type=checkbox]');
		for (var i = 0; i < boxes.length; i++)
			if (boxes[i].checked) out.push(boxes[i].value);
		return out;
	}

	// 需要隐藏的字段 = 全部受控字段 - 已勾选平台对应的字段
	function controlled() {
		var all = [];
		for (var k in MAP)
			for (var i = 0; i < MAP[k].length; i++) all.push(MAP[k][i]);
		return all;
	}

	function apply() {
		var on = selected();
		var wanted = {};
		for (var i = 0; i < on.length; i++) {
			var f = MAP[on[i]];
			if (f) for (var j = 0; j < f.length; j++) wanted[f[j]] = true;
		}

		// 1) 显示/隐藏直接受控的字段
		var all = controlled();
		for (var i = 0; i < all.length; i++) {
			var el = document.getElementById(rowId(all[i]));
			if (!el) continue;
			el.style.display = wanted[all[i]] ? '' : 'none';
			el.setAttribute('data-pb-platform', '1');
		}

		// 2) 二级依赖（自建服务器地址、图标地址、群组编码）由各自开关决定
		var ppOn = on.indexOf('/usr/bin/pushbot/api/pushplus.json') >= 0;
		var gates = [
			['bark_srv',      'bark_srv_enable'],
			['bark_icon',     'bark_icon_enable'],
			['pushdeer_srv',  'pushdeer_srv_enable'],
			['pp_webhook',    'pp_channel'],
			['pp_topic',      'pp_topic_enable']
		];
		for (var g = 0; g < gates.length; g++) {
			var tgt = document.getElementById(rowId(gates[g][0]));
			if (!tgt) continue;
			// PushPlus 未勾选时，其二级字段一律隐藏
			if ((gates[g][0] === 'pp_webhook' || gates[g][0] === 'pp_topic') && !ppOn) {
				tgt.style.display = 'none';
				continue;
			}
			// pp_webhook / pp_topic 是下拉/开关，单独判断
			if (gates[g][0] === 'pp_webhook') {
				var pc = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.pp_channel');
				var pv = '';
				if (pc) { var s = pc.querySelector('select'); if (s) pv = s.value; }
				tgt.style.display = (pv === 'cp' || pv === 'webhook') ? '' : 'none';
			} else if (gates[g][0] === 'pp_topic') {
				var pt = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.pp_topic_enable');
				var pv2 = pt && pt.querySelector('input[type=checkbox]') && pt.querySelector('input[type=checkbox]').checked;
				tgt.style.display = pv2 ? '' : 'none';
			} else {
				var sw = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.' + gates[g][1]);
				var cb = sw && sw.querySelector('input[type=checkbox]');
				tgt.style.display = (cb && cb.checked) ? '' : 'none';
			}
		}

		// 3) 平台分组标题：在每个平台第一个可见字段前插入/更新小标题
		updateDividers(on);
	}

	function updateDividers(on) {
		// 清掉旧标题
		var olds = document.querySelectorAll('.pb-plat-divider');
		for (var i = 0; i < olds.length; i++) olds[i].parentNode.removeChild(olds[i]);

		// 按 DOM 顺序，为每个有可见字段的平台插入标题
		for (var k in MAP) {
			if (on.indexOf(k) < 0) continue;
			var fields = MAP[k];
			var firstEl = null;
			for (var j = 0; j < fields.length; j++) {
				var el = document.getElementById(rowId(fields[j]));
				if (el && el.style.display !== 'none' && el.offsetParent !== null) { firstEl = el; break; }
				if (el && el.style.display !== 'none') { firstEl = el; break; }
			}
			if (!firstEl) continue;
			var div = document.createElement('div');
			div.className = 'pb-plat-divider';
			div.textContent = LABEL[k] || k;
			firstEl.parentNode.insertBefore(div, firstEl);
		}
	}

	function bind() {
		var wrap = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.' + OPT);
		if (!wrap) return false;

		// 复选框变化时重新计算
		if (!wrap.getAttribute('data-pb-bound')) {
			wrap.addEventListener('change', function () { setTimeout(apply, 30); });
			wrap.addEventListener('click',  function () { setTimeout(apply, 30); });
			wrap.setAttribute('data-pb-bound', '1');
		}
		// 二级开关也监听
		['bark_srv_enable','bark_icon_enable','pushdeer_srv_enable'].forEach(function (n) {
			var el = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.' + n);
			if (el && !el.getAttribute('data-pb-bound2')) {
				el.addEventListener('change', function () { setTimeout(apply, 30); });
				el.setAttribute('data-pb-bound2', '1');
			}
		});
		var pcSel = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.pp_channel');
		if (pcSel && !pcSel.getAttribute('data-pb-bound2')) {
			pcSel.addEventListener('change', function () { setTimeout(apply, 30); });
			pcSel.setAttribute('data-pb-bound2', '1');
		}
		var ptEn = document.getElementById('cbid.' + CONFIG + '.' + SECTION + '.pp_topic_enable');
		if (ptEn && !ptEn.getAttribute('data-pb-bound2')) {
			ptEn.addEventListener('change', function () { setTimeout(apply, 30); });
			ptEn.setAttribute('data-pb-bound2', '1');
		}
		return true;
	}

	// 页面是异步渲染的，轮询几次直到控件出现
	var tries = 0;
	function boot() {
		if (bind()) { apply(); setTimeout(apply, 300); setTimeout(apply, 1200); return; }
		if (++tries < 40) setTimeout(boot, 250);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', function () { setTimeout(boot, 200); });
	else
		setTimeout(boot, 200);
})();
