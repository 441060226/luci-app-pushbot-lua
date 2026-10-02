'use strict';
/*
 * 在线设备列表 - 前端逻辑
 * 数据源: /cgi-bin/luci/admin/services/pushbot/clients
 *   ?w=N   实时速率采样秒数 (0=不采样)
 *   &scan=1 主动扫描内网
 *
 * v4: 新增「点击表头排序」
 *   - 8 列全部可排序，按【原始数值】比较（不是格式化文本）
 *   - 三态循环：降序 ▼ → 升序 ▲ → 取消排序（回到默认）
 *   - 排序状态存 localStorage，刷新/重开页面后保留
 *   - 每 30 秒自动刷新不会丢失排序，也不会重复绑定事件
 */
(function () {
	// 由模板注入；若缺失则回退到固定路径
	var API = (typeof window.OC_CLIENTS_API === 'string' && window.OC_CLIENTS_API)
		? window.OC_CLIENTS_API
		: 'admin/services/pushbot/clients';
	var NOTE_API = (typeof window.OC_SETNOTE_API === 'string' && window.OC_SETNOTE_API)
		? window.OC_SETNOTE_API
		: 'admin/services/pushbot/setnote';
	var AUTO_MS = 30000;        // 自动刷新间隔
	var STORE_KEY = 'oc_clients_sort';  // localStorage 键
	var autoTimer = null;
	var busy = false;
	var editing = false;        // 有输入框处于编辑中时，暂停自动刷新渲染
	var lastData = null;        // 最近一次接口数据（供过滤/排序重渲染）
	var activeOnly = true;      // 只看活跃设备

	// ---------- 排序状态 ----------
	// key: null=默认排序；否则为列标识
	// dir: 'desc' | 'asc'
	var sortKey = null;
	var sortDir = 'desc';

	// 各列的原始数值提取器（★ 必须返回数字/字符串原始值，不能返回格式化文本）
	var SORT_VAL = {
		name:    function (c) { return String(c.name || '').toLowerCase(); },
		// 备注列：取输入框里实际显示的值，空则排最后
		note:    function (c) { return String(((c.alias && c.alias !== c.name) ? c.name : '') || '').toLowerCase(); },
		mac:     function (c) { return String(c.mac || '').toLowerCase(); },
		ip:      function (c) {
			// IP 按数值大小排（192.168.5.9 < 192.168.5.25），同段内才正确
			var p = String(c.ip || '').split('.');
			if (p.length !== 4) return -1;
			var n = 0;
			for (var i = 0; i < 4; i++) { n = n * 256 + (parseInt(p[i], 10) || 0); }
			return n;
		},
		live:    function (c) { return (Number(c.live_rx) || 0) + (Number(c.live_tx) || 0); },
		traffic: function (c) { return (Number(c.rx) || 0) + (Number(c.tx) || 0); },
		dur:     function (c) { return Number(c.online_sec) || 0; },
		conns:   function (c) { return Number(c.conns) || 0; }
	};

	function loadSortState() {
		try {
			var s = JSON.parse(localStorage.getItem(STORE_KEY) || 'null');
			if (s && typeof s === 'object') {
				if (s.key && SORT_VAL[s.key]) { sortKey = s.key; sortDir = (s.dir === 'asc' ? 'asc' : 'desc'); }
				else { sortKey = null; sortDir = 'desc'; }
			}
		} catch (e) { /* localStorage 不可用则忽略 */ }
	}

	function saveSortState() {
		try {
			localStorage.setItem(STORE_KEY, JSON.stringify({ key: sortKey, dir: sortDir }));
		} catch (e) { /* 忽略 */ }
	}

	// 默认排序：有实时速率 > 有累计流量 > 其他；同组按名称
	function defaultCompare(a, b) {
		var la = (Number(a.live_rx) || 0) + (Number(a.live_tx) || 0);
		var lb = (Number(b.live_rx) || 0) + (Number(b.live_tx) || 0);
		if (la !== lb) return lb - la;
		var ta = (Number(a.rx) || 0) + (Number(a.tx) || 0);
		var tb = (Number(b.rx) || 0) + (Number(b.tx) || 0);
		if (ta !== tb) return tb - ta;
		return String(a.name || '').localeCompare(String(b.name || ''));
	}

	function applySort(list) {
		if (!sortKey || !SORT_VAL[sortKey]) {
			list.sort(defaultCompare);
			return;
		}
		var get = SORT_VAL[sortKey];
		var sign = (sortDir === 'asc') ? 1 : -1;
		list.sort(function (a, b) {
			var va = get(a), vb = get(b);
			var r;
			if (typeof va === 'number' && typeof vb === 'number') {
				r = va - vb;
			} else {
				r = String(va).localeCompare(String(vb), 'zh-Hans-CN');
			}
			if (r !== 0) return r * sign;
			return defaultCompare(a, b);    // 值相同时用默认排序兜底，保证稳定
		});
	}

	// 把当前排序状态画到表头（箭头 + 高亮 + aria-sort）
	function paintHeaders() {
		var ths = document.querySelectorAll('#oc-table th[data-sort-key]');
		for (var i = 0; i < ths.length; i++) {
			var th = ths[i];
			var k = th.getAttribute('data-sort-key');
			if (sortKey && k === sortKey) {
				th.setAttribute('data-sort-direction', sortDir);
				th.setAttribute('aria-sort', sortDir === 'asc' ? 'ascending' : 'descending');
			} else {
				th.removeAttribute('data-sort-direction');
				th.removeAttribute('aria-sort');
			}
		}
	}

	// 表头点击 → 三态循环
	function onHeaderClick(th) {
		var k = th.getAttribute('data-sort-key');
		if (!k || !SORT_VAL[k]) return;

		if (sortKey !== k) {
			// 换列：默认从降序开始（流量/连接数等看大值更有意义）
			sortKey = k;
			sortDir = 'desc';
		} else if (sortDir === 'desc') {
			sortDir = 'asc';
		} else {
			// 第三态：取消排序，回到默认
			sortKey = null;
			sortDir = 'desc';
		}

		saveSortState();
		paintHeaders();
		if (lastData) render(lastData);
	}

	// ★ 只在 init() 里绑定一次；重渲染只换 tbody，不换 thead，所以不会重复绑定
	function bindHeaders() {
		var ths = document.querySelectorAll('#oc-table th[data-sort-key]');
		for (var i = 0; i < ths.length; i++) {
			(function (th) {
				th.classList.add('oc-sortable');
				th.addEventListener('click', function () { onHeaderClick(th); });
				th.addEventListener('keydown', function (ev) {
					if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); onHeaderClick(th); }
				});
			})(ths[i]);
		}
	}

	// ---------- 工具 ----------
	function q(id) { return document.getElementById(id); }

	function fmtBytes(n) {
		n = Number(n) || 0;
		if (n <= 0) return '0 B';
		var u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
		while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
		return (i === 0 ? n.toFixed(0) : n.toFixed(2)) + ' ' + u[i];
	}

	function fmtRate(bps) {
		bps = Number(bps) || 0;
		if (bps <= 0) return '';
		if (bps >= 1048576) return (bps / 1048576).toFixed(2) + ' MB/s';
		if (bps >= 1024) return (bps / 1024).toFixed(1) + ' KB/s';
		return bps.toFixed(0) + ' B/s';
	}

	function fmtDur(sec) {
		sec = Math.max(0, Number(sec) || 0);
		var d = Math.floor(sec / 86400),
			h = Math.floor((sec % 86400) / 3600),
			m = Math.floor((sec % 3600) / 60);
		if (d > 0) return d + '天' + (h > 0 ? h + '小时' : '');
		if (h > 0) return h + '小时' + (m > 0 ? m + '分' : '');
		if (m > 0) return m + '分';
		return '刚刚';
	}

	function esc(s) {
		return String(s == null ? '' : s)
			.replace(/&/g, '&amp;').replace(/</g, '&lt;')
			.replace(/>/g, '&gt;').replace(/"/g, '&quot;');
	}

	function setStatus(html, isErr) {
		var el = q('oc-status');
		if (!el) return;
		el.innerHTML = html || '';
		// 用 CSS 变量取色，深浅主题下都可读
		el.style.color = isErr ? 'var(--oc-dl, #c0392b)' : 'var(--oc-text-muted, #666)';
	}

	// ---------- 渲染 ----------
	function render(data) {
		lastData = data;
		var body = q('oc-body');
		if (!body) return;

		var list = ((data && data.clients) || []).slice();

		// 过滤：只看活跃设备（有流量 或 有实时速率 或 有连接）
		var total = list.length;
		if (activeOnly) {
			list = list.filter(function (c) {
				return (Number(c.rx) || 0) > 0 ||
					(Number(c.tx) || 0) > 0 ||
					(Number(c.live_rx) || 0) > 0 ||
					(Number(c.live_tx) || 0) > 0 ||
					(Number(c.conns) || 0) > 0;
			});
		}

		// 排序：用户指定优先，否则用默认排序
		applySort(list);

		var hint = '';
		if (activeOnly && list.length < total) {
			hint = '<div class="oc-hint">已隐藏 ' + (total - list.length) +
				' 台无流量设备（取消勾选「只看活跃设备」可查看全部）</div>';
		}

		if (!list.length) {
			body.innerHTML =
				'<tr><td colspan="8" class="oc-empty">' +
				'<div>' + (total ? '暂无活跃设备' : '未发现在线设备') + '</div>' +
				hint.replace('<div class="oc-hint">', '<div class="oc-hint" style="margin-top:6px">') +
				'<div class="oc-hint">可点击「扫描内网」主动探测，或稍后重试</div>' +
				'</td></tr>';
			return;
		}

		var rows = [];
		for (var i = 0; i < list.length; i++) {
			var c = list[i];
			var dl = fmtRate(c.live_rx), ul = fmtRate(c.live_tx);
			var liveCls = (dl || ul) ? 'oc-live' : 'oc-live idle';
			var liveHtml = (dl || ul)
				? (dl ? '<span class="oc-dl">↓' + dl + '</span>' : '') +
				  (ul ? '<span class="oc-ul">↑' + ul + '</span>' : '')
				: '—';

			var nameHtml = '<span class="oc-name">' + esc(c.name || '未知设备') + '</span>';
			if (c.alias && c.alias !== c.name) {
				nameHtml += '<span class="oc-alias">' + esc(c.alias) + '</span>';
			}

			// 备注输入框：有备注时 c.name 就是备注、c.alias 是原名；
			// 无备注时 c.name 是原名，输入框留空。
			var noteVal = (c.alias && c.alias !== c.name) ? c.name : '';
			var noteHtml = '<input type="text" class="oc-note" data-mac="' + esc(c.mac) +
				'" data-orig="' + esc(noteVal) + '" placeholder="点此填写备注" value="' +
				esc(noteVal) + '">';

			var rxN = Number(c.rx) || 0, txN = Number(c.tx) || 0;
			var trafficHtml;
			if (rxN <= 0 && txN <= 0) {
				trafficHtml = '<span style="color:var(--oc-text-faint, #b8c2cc)">—</span>';
			} else {
				trafficHtml =
					(rxN > 0 ? '<span class="oc-dl">↓' + fmtBytes(rxN) + '</span>' : '') +
					(txN > 0 ? '<span class="oc-ul">↑' + fmtBytes(txN) + '</span>' : '');
			}

			rows.push(
				'<tr>' +
				'<td>' + nameHtml + '</td>' +
				'<td>' + noteHtml + '</td>' +
				'<td class="oc-mono">' + esc(c.mac) + '</td>' +
				'<td class="oc-mono">' + esc(c.ip) + '</td>' +
				'<td class="' + liveCls + '">' + liveHtml + '</td>' +
				'<td class="oc-num oc-traffic">' + trafficHtml + '</td>' +
				'<td class="oc-num">' + esc(fmtDur(c.online_sec)) + '</td>' +
				'<td class="oc-num">' + (Number(c.conns) || 0) + '</td>' +
				'</tr>'
			);
		}
		body.innerHTML = rows.join('');
		bindNotes();
	}

	// ---------- 备注输入：失焦/回车保存 ----------
	function saveNote(input) {
		var mac = input.getAttribute('data-mac');
		var orig = input.getAttribute('data-orig') || '';
		var val = input.value.trim();
		if (val === orig) return;           // 未变化

		input.classList.remove('saved', 'err');
		input.classList.add('saving');
		input.disabled = true;

		var fd = new URLSearchParams();
		fd.append('mac', mac);
		fd.append('note', val);

		fetch(NOTE_API, {
			method: 'POST',
			credentials: 'same-origin',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
			body: fd.toString()
		})
			.then(function (r) { return r.json(); })
			.then(function (res) {
				if (!res || !res.ok) throw new Error((res && res.error) || '保存失败');
				input.classList.remove('saving');
				input.classList.add('saved');
				input.setAttribute('data-orig', val);
				setTimeout(function () { input.classList.remove('saved'); }, 1200);
				load();                     // 重新拉取，让「客户端名」列同步为备注名
			})
			.catch(function (e) {
				input.classList.remove('saving');
				input.classList.add('err');
				setStatus('备注保存失败：' + e.message, true);
			})
			.then(function () { input.disabled = false; });
	}

	function bindNotes() {
		var inputs = document.querySelectorAll('.oc-note');
		for (var i = 0; i < inputs.length; i++) {
			(function (el) {
				el.addEventListener('focus', function () { editing = true; });
				el.addEventListener('blur', function () {
					editing = false;
					saveNote(el);
				});
				el.addEventListener('keydown', function (ev) {
					if (ev.key === 'Enter') { ev.preventDefault(); el.blur(); }
					if (ev.key === 'Escape') { el.value = el.getAttribute('data-orig') || ''; el.blur(); }
				});
			})(inputs[i]);
		}
	}

	// ---------- 拉取 ----------
	function load(opts) {
		opts = opts || {};
		if (busy) return;
		busy = true;

		var btns = [q('oc-refresh'), q('oc-scan')];
		for (var i = 0; i < btns.length; i++) if (btns[i]) btns[i].disabled = true;

		var url = API + '?w=' + (opts.scan ? 2 : 1) + (opts.scan ? '&scan=1' : '');
		setStatus((opts.scan ? '<span class="oc-spin"></span>正在扫描内网并采样…'
			: '<span class="oc-spin"></span>加载中…'), false);

		fetch(url, { credentials: 'same-origin' })
			.then(function (r) {
				if (!r.ok) throw new Error('HTTP ' + r.status);
				return r.json();
			})
			.then(function (data) {
				if (editing) { return; }    // 正在编辑备注时跳过本次渲染，避免输入被打断
				render(data);
				var t = new Date().toLocaleTimeString();
				var body = q('oc-body');
				var shown = body
					? [].filter.call(body.querySelectorAll('tr'), function (tr) {
						return !tr.querySelector('.oc-empty');
					}).length
					: 0;
				setStatus('共 ' + (data.count || 0) + ' 台 · 显示 ' + shown +
					' 台 · 更新于 ' + t, false);
			})
			.catch(function (e) {
				setStatus('加载失败：' + e.message, true);
				var body = q('oc-body');
				if (body) body.innerHTML =
					'<tr><td colspan="8" class="oc-empty">加载失败：' +
					esc(e.message) + '</td></tr>';
			})
			.then(function () {
				busy = false;
				for (var j = 0; j < btns.length; j++) if (btns[j]) btns[j].disabled = false;
			});
	}

	// ---------- 自动刷新 ----------
	function startAuto() {
		if (autoTimer) return;
		autoTimer = setInterval(function () {
			if (document.hidden) return;
			load();
		}, AUTO_MS);
	}

	// ---------- 初始化 ----------
	function init() {
		var r = q('oc-refresh');
		if (r) r.addEventListener('click', function () { load(); });
		var s = q('oc-scan');
		if (s) s.addEventListener('click', function () { load({ scan: true }); });

		var ao = q('oc-active-only');
		if (ao) {
			activeOnly = !!ao.checked;
			ao.addEventListener('change', function () {
				activeOnly = !!ao.checked;
				if (lastData) {
					render(lastData);
				} else {
					load();
				}
			});
		}

		// ★ 排序：先恢复状态，再绑定表头（只绑一次），最后加载数据
		loadSortState();
		bindHeaders();
		paintHeaders();

		load();
		startAuto();

		window.addEventListener('beforeunload', function () {
			if (autoTimer) { clearInterval(autoTimer); autoTimer = null; }
		});
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
