// ブラウザでの自動の確認の土台。Web 書き出しを手元で配り、窓なし・消音・使い捨てのプロフィールの Chrome / Edge を
// CDP で操作する。ゲームの状態は、デバッグ用の窓口(?debug=1 の時の window.pdState)から読むだけで、入力は本物のマウス・キー・タッチを送る。
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
// 確かめる Web 書き出し。別の場所の書き出し(ほかのブランチの物など)を確かめる時は、環境変数 PD_WEB にフォルダを入れる
export const WEB = process.env.PD_WEB ? path.resolve(process.env.PD_WEB) : path.join(ROOT, 'build', 'web');
// 書き出しの中に、そのスクリプトが入っているか(例: 'ui/title.gd')。まだ合流していない画面の確認を飛ばすのに使う
export const inBuild = (resPath) => readFileSync(path.join(WEB, 'index.pck')).includes(resPath);
export const OUT = path.join(ROOT, 'build', 'web_shots');
export const SAVE_KEY = 'parry-duel/save'; // save/save_store.gd の WEB_KEY
// 何人かで同時に動かす時は、環境変数でポートをずらす
const HTTP_PORT = Number(process.env.PD_HTTP_PORT || 8791);
const CDP_PORT = Number(process.env.PD_CDP_PORT || 9791);
const BOOT_TIMEOUT_MS = 60000;
export const BROWSERS = {
	chrome: process.env.PD_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
	edge: process.env.PD_EDGE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};
export const PHONE = { width: 540, height: 960, deviceScaleFactor: 1, mobile: false }; // 720 × 1280 の 0.75 倍
export const DESKTOP = { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false };
export const MOBILE = { width: 390, height: 844, deviceScaleFactor: 3, mobile: true };
// 動きを確かめる時のスマホ。ソフト描画で 3 倍密度だと 1 フレームが長くなり、ゲームが「裏にいた」と見て止まることがあるので、密度は 1
export const MOBILE_1X = { ...MOBILE, deviceScaleFactor: 1 };
const KEYS = {
	Space: { key: ' ', code: 'Space', windowsVirtualKeyCode: 32, text: ' ' },
	Enter: { key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, text: '\r' },
	Escape: { key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 },
	KeyX: { key: 'x', code: 'KeyX', windowsVirtualKeyCode: 88, text: 'x' },
	KeyZ: { key: 'z', code: 'KeyZ', windowsVirtualKeyCode: 90, text: 'z' },
	KeyR: { key: 'r', code: 'KeyR', windowsVirtualKeyCode: 82, text: 'r' },
	ShiftLeft: { key: 'Shift', code: 'ShiftLeft', windowsVirtualKeyCode: 16, location: 1 },
	ShiftRight: { key: 'Shift', code: 'ShiftRight', windowsVirtualKeyCode: 16, location: 2 },
};

let failures = 0;
export function expect(ok, label) {
	console.log(`${ok ? 'OK' : 'NG'}  ${label}`);
	if (!ok) failures++;
	return ok;
}
export const failureCount = () => failures;
export { sleep };

export async function waitFor(fn, timeoutMs, everyMs = 250) {
	const end = Date.now() + timeoutMs;
	while (Date.now() < end) {
		const v = await fn();
		if (v) return v;
		await sleep(everyMs);
	}
	return null;
}

async function connect(url) {
	const ws = new WebSocket(url);
	await new Promise((ok, ng) => { ws.onopen = ok; ws.onerror = ng; });
	let id = 0;
	const pending = new Map();
	const listeners = [];
	ws.onmessage = (m) => {
		const msg = JSON.parse(m.data);
		if (msg.id && pending.has(msg.id)) {
			const { ok, ng } = pending.get(msg.id);
			pending.delete(msg.id);
			msg.error ? ng(new Error(msg.error.message)) : ok(msg.result);
		} else listeners.forEach((f) => f(msg));
	};
	return {
		send: (method, params = {}) => new Promise((ok, ng) => {
			const i = ++id;
			pending.set(i, { ok, ng });
			ws.send(JSON.stringify({ id: i, method, params }));
		}),
		onEvent: (f) => listeners.push(f),
		close: () => ws.close(),
	};
}

// build/web を /parry-duel/ の下に置いて配る(Pages と同じ形)。{ url, stop }
// 環境変数 PD_URL に URL(最後は /)を入れると、手元で配らずに、その URL(公開した物など)を確かめる。
export function serve() {
	if (process.env.PD_URL) return { url: process.env.PD_URL, stop: () => {} };
	if (!existsSync(path.join(WEB, 'index.html'))) throw new Error('build/web/index.html が無い(先に python tools/gd.py export)');
	const root = mkdtempSync(path.join(tmpdir(), 'pd-site-'));
	symlinkSync(WEB, path.join(root, 'parry-duel'), 'junction');
	const server = spawn('python', ['-m', 'http.server', String(HTTP_PORT), '--bind', '127.0.0.1', '--directory', root], { stdio: 'ignore' });
	return {
		url: `http://127.0.0.1:${HTTP_PORT}/parry-duel/`,
		stop: () => { server.kill(); rmSync(path.join(root, 'parry-duel')); }, // ジャンクションだけ消す(build/web は残す)
	};
}

// ブラウザを 1 つ立てて、ページを開く。gpu を真にすると、ソフト描画でなく本物の GPU を使わせてみる。
export async function open(name, url, { metrics = PHONE, touch = false, gpu = false } = {}) {
	const exe = BROWSERS[name];
	if (!existsSync(exe)) return null;
	mkdirSync(OUT, { recursive: true });
	const profile = mkdtempSync(path.join(tmpdir(), `pd-${name}-`));
	const args = ['--headless=new', '--mute-audio', `--remote-debugging-port=${CDP_PORT}`, `--user-data-dir=${profile}`,
		'--no-first-run', '--no-default-browser-check', '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
		...(gpu ? ['--enable-gpu', '--use-angle=d3d11', '--ignore-gpu-blocklist'] : ['--enable-unsafe-swiftshader']), 'about:blank'];
	const proc = spawn(exe, args, { stdio: 'ignore' });
	const target = await waitFor(async () => {
		try { return (await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json()).find((t) => t.type === 'page'); }
		catch { return null; }
	}, BOOT_TIMEOUT_MS);
	if (!target) { proc.kill(); throw new Error(`${name}: ブラウザにつながらない`); }
	const cdp = await connect(target.webSocketDebuggerUrl);
	const logs = [];
	const requests = [];
	const urls = new Map(); // requestId → URL
	const sizes = {}; // ファイル名 → 転送したバイト数
	let bytes = 0;
	cdp.onEvent((msg) => {
		const p = msg.params;
		if (msg.method === 'Runtime.consoleAPICalled') logs.push({ level: p.type, text: p.args.map((a) => a.value ?? a.description).join(' ') });
		else if (msg.method === 'Runtime.exceptionThrown') logs.push({ level: 'exception', text: p.exceptionDetails.exception?.description ?? p.exceptionDetails.text });
		else if (msg.method === 'Log.entryAdded') logs.push({ level: p.entry.level, text: `${p.entry.text} ${p.entry.url ?? ''}` });
		else if (msg.method === 'Network.requestWillBeSent' && /^https?:/.test(p.request.url)) { // data: と blob: は通信ではない
			requests.push({ at: Date.now(), url: p.request.url });
			urls.set(p.requestId, p.request.url);
		} else if (msg.method === 'Network.webSocketCreated') requests.push({ at: Date.now(), url: p.url });
		else if (msg.method === 'Network.loadingFinished') {
			bytes += p.encodedDataLength;
			const file = path.posix.basename(new URL(urls.get(p.requestId) ?? 'http://x/?').pathname) || 'index.html';
			sizes[file] = (sizes[file] ?? 0) + p.encodedDataLength;
		}
	});
	for (const m of ['Runtime.enable', 'Log.enable', 'Page.enable', 'Network.enable']) await cdp.send(m);
	await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
	await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: true });
	if (touch) await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
	await cdp.send('Emulation.setDeviceMetricsOverride', metrics);
	const t0 = Date.now();
	await cdp.send('Page.navigate', { url });
	const booted = await waitFor(() => logs.some((l) => l.text.startsWith('Godot Engine v')), BOOT_TIMEOUT_MS, 50);
	const bootMs = Date.now() - t0;

	const evaluate = async (expression) => (await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result.value;
	const http = (what) => fetch(`http://127.0.0.1:${CDP_PORT}/json/${what}`, { method: 'PUT' });
	const page = {
		name, cdp, logs, requests, booted: booted !== null, bootMs, t0,
		bytes: () => bytes,
		sizes: () => ({ ...sizes }),
		evaluate,
		// 同じプロフィールのまま、別の URL を開き直す(保存が残っているかを見る時に使う)。Godot が起動するまで待つ
		goto: async (to) => {
			const from = logs.length;
			await cdp.send('Page.navigate', { url: to });
			return await waitFor(() => logs.slice(from).some((l) => l.text.startsWith('Godot Engine v')), BOOT_TIMEOUT_MS, 50) !== null;
		},
		// ブラウザの中の保存(localStorage の parry-duel/save。save/save_store.gd)を読む。無ければ null
		saved: async () => JSON.parse(await evaluate(`localStorage.getItem('${SAVE_KEY}')`) ?? 'null'),
		// IndexedDB の /userfs(Godot の user:// の実体。同じサイトの Godot のゲーム全部で 1 つ)にある鍵の一覧
		userfsKeys: async () => JSON.parse(await evaluate(`(async () => {
			if (!(await indexedDB.databases()).some((d) => d.name === '/userfs')) return '[]';
			const db = await new Promise((ok, ng) => { const r = indexedDB.open('/userfs'); r.onsuccess = () => ok(r.result); r.onerror = () => ng(r.error); });
			const keys = await new Promise((ok) => { const r = db.transaction('FILE_DATA').objectStore('FILE_DATA').getAllKeys(); r.onsuccess = () => ok(r.result); r.onerror = () => ok([]); });
			db.close();
			return JSON.stringify(keys);
		})()`)),
		// /userfs にファイルを入れる(別のゲームや v0.1.1 までが書いた物の代わり)。files は { パス: 中身の文字 }。
		// Godot が起動して /userfs を作った後に呼ぶ。IDBFS と同じ形で、入れる先のフォルダの項目も足す
		userfsPut: (files) => evaluate(`(async () => {
			const db = await new Promise((ok, ng) => { const r = indexedDB.open('/userfs'); r.onsuccess = () => ok(r.result); r.onerror = () => ng(r.error); });
			const tx = db.transaction('FILE_DATA', 'readwrite');
			const store = tx.objectStore('FILE_DATA');
			const now = new Date();
			for (const [p, text] of Object.entries(${JSON.stringify(files)})) {
				store.put({ timestamp: now, mode: 0o40777 }, p.slice(0, p.lastIndexOf('/')));
				store.put({ timestamp: now, mode: 0o100666, contents: new TextEncoder().encode(text) }, p);
			}
			await new Promise((ok, ng) => { tx.oncomplete = ok; tx.onerror = () => ng(tx.error); });
			db.close();
			return true;
		})()`),
		// デバッグ用の窓口の状態(?debug=1 の時だけ出る)
		state: async () => { try { return JSON.parse(await evaluate('window.pdState') || '{}'); } catch { return {}; } },
		waitState: async (pred, timeoutMs = 15000, everyMs = 8) => waitFor(async () => { const s = await page.state(); return pred(s) ? s : null; }, timeoutMs, everyMs),
		// ビューポートの座標(720×1280 より広いことがある)→ CSS の px
		toCss: async (s, x, y) => { const w = await evaluate('window.innerWidth'); const k = w / s.vp[0]; return [x * k, y * k]; },
		// ゲームの座標(720×1280 の中)→ CSS の px
		gameCss: async (s, gx, gy) => page.toCss(s, s.stage[0] + gx, s.stage[1] + gy),
		mouse: async (x, y) => {
			await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
			await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
		},
		// 指を置く。points は今触れている指の全部([x, y] の並び。番号は並びの順)。指を足す時は、前からの指も入れる
		touchStart: (points) => cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: points.map(([x, y], id) => ({ x, y, id })) }),
		touchEnd: () => cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }),
		touch: async (points) => {
			await page.touchStart(points);
			await page.touchEnd();
		},
		// repeat を真にすると、押しっぱなしのくり返し(ブラウザの keydown の repeat)として届く
		keyDown: (k, repeat = false) => cdp.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...KEYS[k], text: undefined, autoRepeat: repeat }),
		keyUp: (k) => cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', ...KEYS[k], text: undefined }),
		key: async (k) => {
			await page.keyDown(k);
			await page.keyUp(k);
		},
		// タブを裏に回す(別のタブを作って前に出す)/ 前に戻す。裏の間は document.visibilityState が hidden になる
		hide: async () => {
			await cdp.send('Emulation.setFocusEmulationEnabled', { enabled: false });
			await http('new?about:blank');
		},
		show: () => http(`activate/${target.id}`),
		// 名前でボタンを押す(見えていて押せるボタンだけが state.buttons に出る)
		clickButton: async (buttonName, how = 'mouse') => {
			const s = await page.waitState((st) => st.buttons && st.buttons[buttonName], 8000);
			if (!s) return false;
			const [x, y] = await page.toCss(s, ...s.buttons[buttonName]);
			if (how === 'touch') await page.touch([[x, y]]);
			else await page.mouse(x, y);
			return true;
		},
		// 撮る。clip([x, y, w, h]。CSS の px)を渡すと、その範囲だけ
		shot: async (label, clip = null) => {
			const file = path.join(OUT, `${name}_${label}.png`);
			const params = clip ? { clip: { x: clip[0], y: clip[1], width: clip[2], height: clip[3], scale: 1 } } : {};
			writeFileSync(file, Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png', ...params })).data, 'base64'));
			return file;
		},
		errors: () => logs.filter((l) => ['error', 'exception'].includes(l.level) && !l.text.includes('favicon.ico')),
		close: async () => {
			try { await cdp.send('Browser.close'); } catch { /* もう閉じた */ }
			cdp.close();
			await Promise.race([new Promise((ok) => proc.once('exit', ok)), sleep(3000)]);
			proc.kill();
			rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
		},
	};
	return page;
}

export const stats = (list) => {
	if (!list.length) return { n: 0 };
	const s = [...list].sort((a, b) => a - b);
	return { n: s.length, p50: s[Math.floor(s.length / 2)], p95: s[Math.min(Math.ceil(s.length * 0.95) - 1, s.length - 1)], max: s[s.length - 1] };
};
