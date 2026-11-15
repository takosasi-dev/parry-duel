// Web 書き出しを、窓なし・消音・使い捨てのプロフィールの Chrome / Edge で動かして確かめる。画像は build/web_shots/
// 状態は ?debug=1 の window.pdState から読むだけ。入力は本物のキー・マウス・タッチを CDP で送る(?auto=1 は速さと見た目にだけ使う)。
//   node tests/web_drive.mjs --boot               起動・コンソール・転送量・起動の時間 3 回・通信先(NFR-5)
//   node tests/web_drive.mjs --keys               キーとマウスの割り当て(スペース・X = 弾く、Z・左シフト = 避ける、くり返しは捨てる、Esc = 一時停止、余りの所の押し)
//   node tests/web_drive.mjs --touch2             タッチの二重入力と、2 本の指(AC-28・E-1・E-2)
//   node tests/web_drive.mjs --pause              一時停止とタブが裏の間、tick が進まない(AC-29・E-9・E-10)
//   node tests/web_drive.mjs --play [key|mouse|touch]   敵 3 の練習を、本物の入力で倒し切る(AC-27・AC-28 の対戦の部分)
//   node tests/web_drive.mjs --lose               負けて「この敵からやり直す」(E-13・NFR-6)
//   node tests/web_drive.mjs --flow [key|mouse|touch] [--daily]   タイトル → 対戦 → 合間 → 結果 → コピー → タイトル → 読み込み直し(AC-27・AC-28・保存)。--daily は「今日の3連戦」
//   node tests/web_drive.mjs --settings           設定を変えて、読み込み直した後も残る(localStorage への保存)
//   node tests/web_drive.mjs --storage            別のタブ・別のゲームの保存を消さない、v0.1.1 までの保存を引き継ぐ
//   node tests/web_drive.mjs --drill              型の練習: 型を選んで、本物のキーで繰り返し弾く(v0.2.0)
//   node tests/web_drive.mjs --pad                ゲームパッド: 偽のパッドで、メニューを選んで押す・対戦で弾く・一時停止(v0.2.0)
//   node tests/web_drive.mjs --endless            終わらない連戦: 1 体倒して合間・負けて結果・記録と実績が保存に届く(v0.3.0)
//   node tests/web_drive.mjs --latency [key|mouse|touch] [--gpu]   入力から描画までの時間を、押し 100 回ぶん測る(NFR-2・仕様書 §8.2)
//   node tests/web_drive.mjs --perf               自動の相手に 60 秒戦わせた 1 フレームの時間(NFR-1。窓なしなので参考値)
//   node tests/web_drive.mjs --quiet              読み込みの後、3 分間の通信が 0 件(NFR-8・AC-31)
//   node tests/web_drive.mjs --shots              全部の画面(タイトル・対戦・一時停止・合間・結果・設定・タイミング合わせ)を撮り、README 用を docs/ に置く(白黒の版も。NFR-11)
//   node tests/web_drive.mjs --gif                README 用の動く画像 docs/play.gif(ffmpeg が要る。無ければ飛ばす)
//   node tests/web_drive.mjs --look [duel|duel2|duel3|calib] [--desktop]   自動の相手に戦わせて、0.6 秒おきに撮る
//   node tests/web_drive.mjs --all                上を順に全部
// --browsers=chrome,edge で使うブラウザを絞れる。ポートは環境変数 PD_HTTP_PORT・PD_CDP_PORT、確かめる書き出しは PD_WEB(既定は build/web)。
// 失敗が 1 件でもあれば終了コード 1。
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { gzipSync } from 'node:zlib';
import { BROWSERS, DESKTOP, MOBILE_1X, PHONE, SAVE_KEY, WEB, expect, failureCount, inBuild, open, serve, sleep } from './web/lib.mjs';
import { PARRY_TYPES, count, hasMenus, newTally, playFlow, playLose, playPractice, presser, take, waitSaved } from './web/play.mjs';
import { gif, shots } from './web/shots.mjs';

const args = process.argv.slice(2);
const has = (flag) => args.includes(flag);
const valueOf = (flag) => { const v = args[args.indexOf(flag) + 1]; return has(flag) && v && !v.startsWith('--') ? v : null; };
const gpu = has('--gpu');
const only = args.find((a) => a.startsWith('--browsers='))?.slice('--browsers='.length).split(',');
const browsers = (dflt = Object.keys(BROWSERS)) => (only ?? dflt).filter((n) => existsSync(BROWSERS[n] ?? '') || (console.log(`--  ${n}: 入っていない`), false));
const mb = (n) => `${(n / 1e6).toFixed(2)} MB`;

const QUIET_MS = 180000;
const PERF_MS = 60000;
const BOOT_RUNS = 3;
const BOOT_LIMIT_MS = 10000; // NFR-5(仮)

// ページを開いて fn を回し、必ず閉じる。途中の例外は NG に数えて、次のモードへ進む
async function withPage(name, url, opt, fn) {
	let page = null;
	try {
		page = await open(name, url, opt);
		if (!page) return;
		if (expect(page.booted, `${name}: Godot が起動した(${page.bootMs} ms)`)) await fn(page);
	} catch (e) {
		expect(false, `${name}: 途中で止まった: ${e.stack ?? e}`);
	} finally { await page?.close(); }
}

const noErrors = (page) => {
	page.errors().forEach((l) => console.log(`    [${l.level}] ${l.text}`));
	expect(page.errors().length === 0, `${page.name}: コンソールにエラーが無い`);
};
const duelReady = (page) => page.waitState((s) => s.duel && s.duel.state === 'PATTERN', 20000);

// 硬直が明けていて、近く(45 tick 以内)に当たる攻撃が無い時を待つ。この時に押した 弾く は必ず空振りになるので、数が決まる
const waitFree = (page) => page.waitState((s) => s.duel && !s.duel.over && s.duel.lock === 0 && s.duel.freeze === 0 && s.duel.hurt === 0
	&& s.duel.attacks.every((a) => a.judged - s.duel.tick > 45), 12000);

// act() の入力 1 つで、弾く系・避けるの出来事がいくつ増えたか。dom はブラウザに届いた keydown・mousedown・touchstart の数
async function effect(page, act) {
	const before = await waitFree(page);
	if (!before) return { parry: -1, dodge: -1, dom: -1, state: await page.state() };
	const tally = newTally();
	take(before, tally);
	tally.counts = {};
	const dom0 = await page.evaluate('window.pdIn.n');
	await act();
	await sleep(250);
	const state = await page.state();
	take(state, tally);
	return { parry: count(tally, PARRY_TYPES), dodge: tally.counts.dodge ?? 0, dom: (await page.evaluate('window.pdIn.n')) - dom0, state };
}
const show = (r) => `弾く系 ${r.parry}・避ける ${r.dodge}・ブラウザのイベント ${r.dom}`;
const lastInput = (r, n = 1) => r.state.inputs.slice(-n).forEach((t) => console.log(`      ${t}`));

async function boot(base) {
	const wasm = statSync(path.join(WEB, 'index.wasm')).size;
	const pck = statSync(path.join(WEB, 'index.pck')).size;
	const gz = ['index.wasm', 'index.pck', 'index.js', 'index.html'].reduce((n, f) => n + gzipSync(readFileSync(path.join(WEB, f))).length, 0);
	console.log(`    ファイルの大きさ: index.wasm ${mb(wasm)} / index.pck ${mb(pck)}。gzip した時の主な 4 つの合計 ${mb(gz)}(推定。Pages は gzip をかけるが、手元の配信はかけない)`);
	for (const name of browsers()) {
		const times = [];
		for (let i = 0; i < BOOT_RUNS; i++) {
			await withPage(name, `${base}?debug=1`, { metrics: DESKTOP, gpu }, async (page) => {
				const s = await page.waitState((st) => st.frame > 0, 30000, 20);
				times.push(Date.now() - page.t0);
				if (i === 0) console.log(`    ${name}: ${await page.evaluate(GL_NAME)}`);
				if (i > 0) return;
				expect(s !== null && s.screen === 'title', `${name}: 状態が出て、画面が title(${s?.screen})`);
				await sleep(1000);
				const s2 = await page.state();
				expect(s2.frame > s.frame + 20, `${name}: フレームが進んでいる(1 秒で ${s2.frame - s.frame})`);
				console.log(`    描画: ${s2.renderer} / ビューポート ${s2.vp} / 見えているボタン: ${Object.keys(s2.buttons).join(' ') || '(無い)'}`);
				const sizes = page.sizes();
				console.log(`    転送量(キャッシュ無効): index.wasm ${mb(sizes['index.wasm'] ?? 0)} / index.pck ${mb(sizes['index.pck'] ?? 0)} / 合計 ${mb(page.bytes())}(${page.requests.length} 件)`);
				const hosts = [...new Set(page.requests.map((r) => new URL(r.url).host))];
				expect(hosts.length === 1, `${name}: 通信先が配信元の 1 か所だけ(${hosts.join(', ')})`);
				await page.shot('boot');
				noErrors(page);
			});
		}
		console.log(`    ${name}: 開いてから状態が出るまで ${times.join(' / ')} ms(手元の配信。回線の時間は入らない)`);
		expect(times.length === BOOT_RUNS && times.every((t) => t <= BOOT_LIMIT_MS), `${name}: ${BOOT_RUNS} 回とも ${BOOT_LIMIT_MS / 1000} 秒以内(NFR-5)`);
	}
	// 本番と同じ URL(?debug=1 なし)では、デバッグ用の窓口が出ない
	await withPage(browsers()[0], base, { metrics: DESKTOP }, async (page) => {
		await sleep(2000);
		expect(await page.evaluate('typeof window.pdState') === 'undefined', `${page.name}: ?debug=1 が無ければ window.pdState は無い`);
		await page.shot('boot_plain');
		noErrors(page);
	});
}

async function keys(base) {
	for (const name of browsers()) {
		await withPage(name, `${base}?debug=1&go=duel`, {}, async (page) => {
			if (!expect(await duelReady(page) !== null, `${name}: 対戦が始まる`)) return;
			for (const [key, parry, dodge, label] of [['Space', 1, 0, 'スペース = 弾く'], ['KeyX', 1, 0, 'X = 弾く'], ['KeyZ', 0, 1, 'Z = 避ける'],
				['ShiftLeft', 0, 1, '左シフト = 避ける'], ['ShiftRight', 0, 0, '右シフト = 何もしない']]) {
				const r = await effect(page, () => page.key(key));
				expect(r.parry === parry && r.dodge === dodge, `${name}: ${label}(${show(r)})`);
				lastInput(r);
			}
			const s = await page.state();
			const right = await page.gameCss(s, 540, 760);
			const left = await page.gameCss(s, 180, 760);
			let r = await effect(page, () => page.mouse(...right));
			expect(r.parry === 1 && r.dodge === 0, `${name}: 右半分のクリック = 弾く(${show(r)})`);
			lastInput(r);
			r = await effect(page, () => page.mouse(...left));
			expect(r.parry === 0 && r.dodge === 1, `${name}: 左半分のクリック = 避ける(${show(r)})`);
			// 押しっぱなし: 最初の 1 回だけが入力になり、くり返しは捨てる
			r = await effect(page, () => page.keyDown('Space'));
			expect(r.parry === 1, `${name}: スペースを押し下げる = 弾く 1 回(${show(r)})`);
			r = await effect(page, async () => { for (let i = 0; i < 3; i++) { await page.keyDown('Space', true); await sleep(40); } });
			expect(r.parry === 0 && r.dodge === 0 && r.dom === 3, `${name}: 押しっぱなしのくり返し 3 回は入力にならない(${show(r)})`);
			lastInput(r);
			await page.keyUp('Space');
			// Esc = 一時停止(今は一時停止の画面が無く、戻れないので最後に押す)
			await waitFree(page);
			await page.key('Escape');
			const paused = await page.waitState((st) => st.duel?.paused, 3000);
			expect(paused !== null && paused.screen === 'pause', `${name}: Esc = 一時停止(screen=${paused?.screen} paused=${paused?.duel.paused})`);
			noErrors(page);
		});
		// 横長の窓: 余りの所(720×1280 の外)を押しても、近い側の半分として扱う(E-20)
		await withPage(name, `${base}?debug=1&go=duel`, { metrics: DESKTOP }, async (page) => {
			const s = await duelReady(page);
			if (!expect(s !== null, `${name}: 横長の窓で対戦が始まる(ビューポート ${s?.vp}、720×1280 の左上 ${s?.stage})`)) return;
			let r = await effect(page, () => page.mouse(DESKTOP.width - 40, 400));
			expect(r.parry === 1 && r.dodge === 0, `${name}: 右の余りをクリック = 弾く(${show(r)})`);
			lastInput(r);
			r = await effect(page, () => page.mouse(40, 400));
			expect(r.parry === 0 && r.dodge === 1, `${name}: 左の余りをクリック = 避ける(${show(r)})`);
		});
	}
}

async function lose(base) {
	for (const name of browsers(['chrome'])) {
		await withPage(name, `${base}?debug=1&go=duel`, {}, async (page) => {
			await playLose(page);
			noErrors(page);
		});
	}
}

async function touch2(base) {
	for (const name of browsers(['chrome'])) {
		await withPage(name, `${base}?debug=1&go=duel`, { metrics: MOBILE_1X, touch: true }, async (page) => {
			const s = await duelReady(page);
			if (!expect(s !== null, `${name}: 対戦が始まる(スマホのエミュレーション ${MOBILE_1X.width}×${MOBILE_1X.height})`)) return;
			console.log(`    ビューポート ${s.vp} / 720×1280 の左上 ${s.stage}`);
			const R = await page.gameCss(s, 540, 760);
			const L = await page.gameCss(s, 180, 760);
			let r = await effect(page, () => page.touch([R]));
			expect(r.parry === 1 && r.dodge === 0, `${name}: (1) 右半分を 1 回タップ → 弾く系が 1 個だけ(2 個なら、模擬のマウスも数えている)(${show(r)})`);
			lastInput(r, 2);
			r = await effect(page, () => page.touch([L]));
			expect(r.parry === 0 && r.dodge === 1, `${name}: (1) 左半分を 1 回タップ → 避ける が 1 個だけ(${show(r)})`);
			r = await effect(page, () => page.touch([L, R]));
			expect(r.parry === 1 && r.dodge === 0, `${name}: (2) 左右を同時に置く → 弾く だけを使う(E-1)(${show(r)})`);
			lastInput(r, 4);
			r = await effect(page, async () => { await page.touchStart([L]); await sleep(30); await page.touchStart([L, R]); await page.touchEnd(); });
			expect(r.parry === 0 && r.dodge === 1, `${name}: (3) 左 → 30 ms 後に右 → 避ける の硬直で右は捨てる(E-2)(${show(r)})`);
			r = await effect(page, async () => { await page.touchStart([R]); await sleep(30); await page.touchStart([R, L]); await page.touchEnd(); });
			expect(r.parry === 1 && r.dodge === 0, `${name}: (3) 右 → 30 ms 後に左 → 空振りの硬直で左は捨てる(E-2)(${show(r)})`);
			// 左の親指を置いたまま、硬直が明けてから右をタップ → 右は別の入力として届く(AC-28)
			r = await effect(page, () => page.touchStart([L]));
			expect(r.dodge === 1, `${name}: (4) 左の指を置く → 避ける(${show(r)})`);
			r = await effect(page, () => page.touchStart([L, R]));
			expect(r.parry === 1 && r.dodge === 0, `${name}: (4) 左を置いたまま右を置く → 弾く が 1 個。左は押し直しにならない(${show(r)})`);
			lastInput(r, 2);
			await page.touchEnd();
			// 一時停止ボタンをタップ → 弾く・避けるにならずに止まる
			const tally = newTally();
			take(await waitFree(page), tally);
			tally.counts = {};
			await page.clickButton('btn_pause', 'touch');
			const paused = await page.waitState((st) => st.duel?.paused, 3000);
			take(paused ?? {}, tally);
			expect(paused !== null && count(tally, [...PARRY_TYPES, 'dodge']) === 0, `${name}: 一時停止ボタンをタップ → 止まり、弾く・避けるにならない`);
			await page.shot('touch2');
			noErrors(page);
		});
	}
}

async function pause(base) {
	for (const name of browsers()) {
		// (1) 一時停止ボタン
		await withPage(name, `${base}?debug=1&go=duel`, {}, async (page) => {
			if (!expect(await duelReady(page) !== null, `${name}: 対戦が始まる`)) return;
			const tally = newTally();
			take(await waitFree(page), tally);
			tally.counts = {};
			expect(await page.clickButton('btn_pause'), `${name}: (1) 一時停止ボタンが押せる`);
			const s0 = await page.waitState((s) => s.duel?.paused, 3000);
			if (!expect(s0 !== null && s0.screen === 'pause', `${name}: (1) ボタンで一時停止になる(screen=${s0?.screen})`)) return;
			await sleep(500);
			await page.key('Space');
			await page.key('KeyZ');
			await sleep(300);
			const s1 = await page.state();
			take(s1, tally);
			expect(s1.duel.tick === s0.duel.tick && s1.frame > s0.frame, `${name}: (1) 止めている 0.8 秒、tick が進まない(${s0.duel.tick} → ${s1.duel.tick}。フレームは ${s1.frame - s0.frame} 進んだ)`);
			expect(count(tally, [...PARRY_TYPES, 'dodge']) === 0, `${name}: (1) ボタンの押しと、止めている間のキーは、弾く・避けるにならない`);
			await page.shot('pause');
			// (3) 「続ける」の後の 1 秒(E-9)。一時停止の画面(ui/pause.gd)が合流してから動く
			if (!inBuild('ui/pause.gd')) { console.log('--  (3) 「続ける」の後の 1 秒: 一時停止の画面がまだ無いので飛ばす'); return; }
			if (!expect(await page.clickButton('btn_resume'), `${name}: (3) 「続ける」が押せる`)) return;
			const w = await page.waitState((s) => s.duel && !s.duel.paused && s.duel.resume_left > 0, 2000);
			expect(w !== null, `${name}: (3) 「続ける」の後、待ちに入る(残り ${w?.duel.resume_left} 秒)`);
			tally.counts = {};
			await sleep(300);
			await page.key('Space');
			await sleep(400);
			const s2 = await page.state();
			take(s2, tally);
			expect(s2.duel.tick === s0.duel.tick && s2.duel.resume_left > 0, `${name}: (3) 「続ける」から 0.7 秒は tick が進まない(${s0.duel.tick} → ${s2.duel.tick})`);
			const s3 = await page.waitState((s) => s.duel && s.duel.tick > s0.duel.tick, 3000);
			take(s3 ?? {}, tally);
			expect(s3 !== null && s3.screen === 'duel', `${name}: (3) 待ちが明けると tick が進む`);
			expect(count(tally, [...PARRY_TYPES, 'dodge']) === 0, `${name}: (3) 待ちの間の入力は捨てられる`);
			// (4) Esc の重なり: 対戦 → Esc(一時停止)→ 設定 → タイミング合わせ → Esc → Esc → Esc(続ける)。その間、対戦は止まったまま
			await page.key('Escape');
			const p0 = await page.waitState((s) => s.screen === 'pause' && s.duel?.paused && s.buttons?.btn_pause_settings, 3000);
			if (!expect(p0 !== null, `${name}: (4) Esc で一時停止の画面が出る`)) return;
			await sleep(300);
			await page.clickButton('btn_pause_settings');
			expect(await page.waitState((s) => s.screen === 'settings', 3000) !== null, `${name}: (4) 一時停止から設定が開く`);
			await page.clickButton('btn_calib');
			expect(await page.waitState((s) => s.screen === 'calib', 3000) !== null, `${name}: (4) 設定からタイミング合わせが開く`);
			await sleep(300);
			const screens = [];
			for (const want of ['settings', 'pause']) {
				await page.key('Escape');
				await sleep(300);
				screens.push((await page.state()).screen);
			}
			const p1 = await page.state();
			expect(screens.join(' → ') === 'settings → pause' && p1.duel.paused && p1.duel.tick === p0.duel.tick,
				`${name}: (4) Esc で 1 つずつ戻り(${screens.join(' → ')})、対戦は止まったまま(tick ${p0.duel.tick} → ${p1.duel.tick})`);
			await page.key('Escape');
			const p2 = await page.waitState((s) => s.screen === 'duel' && !s.duel.paused && s.duel.resume_left > 0, 3000);
			expect(p2 !== null, `${name}: (4) 一時停止の画面の Esc は「続ける」(1 秒の待ちに入る)`);
			// 「タイトルへ」は、今の回を記録に残さずに戻る
			await page.waitState((s) => s.duel && s.duel.resume_left === 0, 3000);
			await page.key('Escape');
			await page.waitState((s) => s.buttons?.btn_pause_title, 3000);
			await sleep(300);
			await page.clickButton('btn_pause_title');
			const t = await page.waitState((s) => s.screen === 'title' && s.buttons?.btn_fixed, 3000);
			expect(t !== null && !t.duel && (await page.saved())?.fixed == null, `${name}: (4) 一時停止の「タイトルへ」でタイトルに戻り、記録は残らない`);
		});
		// (2) タブが裏に回る
		await withPage(name, `${base}?debug=1&go=duel`, {}, async (page) => {
			if (!expect(await duelReady(page) !== null, `${name}: 対戦が始まる`)) return;
			const s0 = await page.state();
			await page.hide();
			const hiddenAt = Date.now();
			await sleep(3000);
			const vis = await page.evaluate('document.visibilityState + " / hasFocus=" + document.hasFocus()');
			const mid = await page.state();
			await page.show();
			await sleep(700);
			const s1 = await page.state();
			const back = await page.evaluate('document.visibilityState');
			console.log(`    裏の間: visibilityState=${vis}、状態の tick ${mid.duel?.tick}(フレーム ${mid.frame})。戻した後: ${back}、tick ${s1.duel?.tick}(フレーム ${s1.frame})`);
			expect(vis.startsWith('hidden'), `${name}: (2) タブが裏に回った(${vis})`);
			expect(s1.duel?.paused === true && s1.screen === 'pause', `${name}: (2) 戻した時に一時停止になっている(paused=${s1.duel?.paused} screen=${s1.screen})`);
			const moved = s1.duel.tick - s0.duel.tick;
			expect(moved >= 0 && moved <= 24, `${name}: (2) 裏にいた ${Date.now() - hiddenAt} ms の間、tick が進んでいない(${s0.duel.tick} → ${s1.duel.tick}。裏に回すまでの数フレームぶんは進む)`);
			expect(s1.duel.hits === s0.duel.hits && s1.duel.player_hp === s0.duel.player_hp, `${name}: (2) 裏の間に当たっていない`);
			noErrors(page);
		});
	}
}

async function play(base, hows) {
	for (const name of browsers()) {
		for (const how of hows) {
			const opt = how === 'touch' ? { metrics: MOBILE_1X, touch: true } : {};
			await withPage(name, `${base}?debug=1&go=duel3`, opt, async (page) => {
				await playPractice(page, how);
				await page.shot(`play_${how}`);
				noErrors(page);
			});
		}
	}
}

async function flow(base, hows) {
	if (!hasMenus()) { console.log('--  --flow: メニューの画面(ui/title.gd・interval.gd・result.gd)がまだ無いので飛ばす'); return; }
	const run = (name, how, daily) => withPage(name, `${base}?debug=1`, how === 'touch' ? { metrics: MOBILE_1X, touch: true } : {}, async (page) => {
		await playFlow(page, how, `${base}?debug=1`, daily);
		noErrors(page);
	});
	for (const name of browsers()) for (const how of hows) await run(name, how, has('--daily'));
	if (has('--all')) await run(browsers()[0], 'mouse', true); // 「今日の3連戦」の入口も 1 回
}

// 設定を変えて、ブラウザの中の保存(localStorage)に届くこと、読み込み直しても残ることを見る。
// 読み込み直すまでの待ちは 5 通り(3 秒・1 秒・0.3 秒・0.1 秒・すぐ)。1 秒未満は間に合わないことがあり得るので、結果を出すだけ
async function settings(base) {
	if (!inBuild('ui/settings.gd')) { console.log('--  --settings: 設定の画面がまだ無いので飛ばす'); return; }
	for (const name of browsers()) {
		await withPage(name, `${base}?debug=1`, {}, async (page) => {
			const openSettings = async () => {
				await page.waitState((s) => s.screen === 'title' && s.buttons?.btn_settings, 30000);
				await page.clickButton('btn_settings');
				return page.waitState((s) => s.screen === 'settings' && s.buttons?.btn_back, 5000);
			};
			if (!expect(await openSettings() !== null, `${name}: タイトルから設定が開く`)) return;
			for (const b of ['btn_vol_25', 'btn_shake_off', 'btn_flash_on', 'btn_offset_plus', 'btn_offset_plus', 'btn_offset_plus']) {
				if (!expect(await page.clickButton(b), `${name}: ${b} が押せる`)) return;
				await sleep(60);
			}
			const t0 = Date.now();
			const want = { volume: 25, shake: false, reduce_flash: true, offset_ticks: 3 };
			const same = (v, w) => JSON.stringify(v?.settings) === JSON.stringify(w);
			let saved = await waitSaved(page, (v) => same(v, want));
			expect(same(saved, want), `${name}: 設定を変えると保存に届く(最後の押しから ${Date.now() - t0} ms 以内。保存: ${JSON.stringify(saved?.settings)})`);
			await page.shot('settings_changed');
			for (const waitMs of [3000, 1000, 300, 100, 0]) {
				// ずれをもう 1 つ進めてから、waitMs 待って読み込み直す。対戦に入って、ずれが効いているかも見る
				want.offset_ticks++;
				await page.clickButton('btn_offset_plus');
				if (waitMs) await sleep(waitMs);
				await page.goto(`${base}?debug=1&go=duel`);
				const s = await duelReady(page);
				saved = await page.saved();
				const ok = s !== null && s.duel.offset === want.offset_ticks && same(saved, want);
				const line = `${name}: 変えて ${waitMs} ms 後に読み込み直す → ${ok ? '残っている' : '残っていない'}(対戦のずれ ${s?.duel.offset} tick、保存: ${JSON.stringify(saved?.settings)})`;
				if (waitMs >= 1000) expect(ok, line); else console.log(`    ${line}(1 秒未満は、結果を出すだけ)`);
				want.offset_ticks = saved?.settings.offset_ticks ?? want.offset_ticks;
				await page.goto(`${base}?debug=1`);
				if (!expect(await openSettings() !== null, `${name}: 読み込み直した後も設定が開く`)) return;
				if (waitMs === 3000) { await sleep(500); await page.shot('settings_reloaded'); }
			}
			// 設定は Esc でタイトルに戻る
			await page.key('Escape');
			expect(await page.waitState((s) => s.screen === 'title', 3000) !== null, `${name}: 設定は Esc でタイトルに戻る`);
			noErrors(page);
		});
	}
}

// 保存の置き場(save/save_store.gd の頭)。同じサイトの Godot のゲームは IndexedDB の /userfs を 1 つ共有するので、
// ParryDuel は localStorage に書く。(1) v0.1.1 までの /userfs の保存を引き継ぐ (2) 起動した後に別のゲームが書いた /userfs を消さない
// (3) 別のタブが書いた良い記録を、こちらの書き込みで消さない
async function storage(base) {
	const LEGACY = '/userfs/godot/app_userdata/ParryDuel/save.json';
	const OTHER = '/userfs/godot/app_userdata/OtherGame/save.json';
	const old = { version: 1, fixed: { hits: 2, ticks: 20000, justs: 5, retries: 0 }, daily: null, reached_boss: 3 };
	const better = { hits: 0, ticks: 15000, justs: 9, retries: 0 };
	for (const name of browsers()) {
		await withPage(name, `${base}?debug=1`, {}, async (page) => {
			const title = () => page.waitState((s) => s.screen === 'title' && s.buttons?.btn_fixed, 30000);
			if (!expect(await title() !== null, `${name}: タイトルが出る`)) return;
			await page.userfsPut({ [LEGACY]: JSON.stringify(old) });
			await page.goto(`${base}?debug=1`);
			const t = await title();
			expect(t !== null && Boolean(t.buttons.btn_practice_3) && await page.saved() === null,
				`${name}: (1) v0.1.1 までの保存(/userfs)を読む。練習の敵 3 が押せる(押せるボタン: ${Object.keys(t?.buttons ?? {}).join(' ')})`);

			await page.userfsPut({ [OTHER]: '{"other":true}' }); // このタブが起動した後に、別のゲームが書いた
			await page.clickButton('btn_settings');
			if (!expect(await page.waitState((s) => s.screen === 'settings', 5000) !== null, `${name}: 設定が開く`)) return;
			await page.clickButton('btn_vol_25');
			let saved = await waitSaved(page, (v) => v?.settings?.volume === 25);
			const sf = (await page.state()).save_failed;
			expect(sf === false, `${name}: 書けた時に「書けなかった」にならない(save_failed: ${sf}。v0.1.2 では毎回 true で、結果の画面に「記録を残せない」が出ていた)`);
			expect(JSON.stringify(saved?.fixed) === JSON.stringify(old.fixed) && saved?.reached_boss === 3,
				`${name}: (1) 書くと、引き継いだ記録ごと localStorage に移る(保存: ${JSON.stringify(saved)})`);
			await sleep(1500); // Godot が /userfs を書き戻すなら、この間に起きる
			const keys = await page.userfsKeys();
			expect(keys.includes(OTHER), `${name}: (2) 起動した後に別のゲームが書いた /userfs の保存が残る(/userfs の鍵: ${keys.join(' ')})`);

			await page.evaluate(`localStorage.setItem('${SAVE_KEY}', JSON.stringify({ ...JSON.parse(localStorage.getItem('${SAVE_KEY}')), fixed: ${JSON.stringify(better)} }))`);
			await page.clickButton('btn_shake_off');
			saved = await waitSaved(page, (v) => v?.settings?.shake === false);
			expect(JSON.stringify(saved?.fixed) === JSON.stringify(better) && saved?.settings?.volume === 25,
				`${name}: (3) 別のタブが書いた良い記録が、こちらの書き込みの後も残る(保存: ${JSON.stringify(saved)})`);

			// 対戦の描画で Godot が user:// に何か(描画のキャッシュなど)を書いても、/userfs を書き戻さない
			const OTHER2 = '/userfs/godot/app_userdata/OtherGame/later.json';
			await page.userfsPut({ [OTHER2]: '{}' });
			await page.key('Escape');
			// 設定から戻るとタイトルを作り直す。入る時の動き(0.3 秒)が終わってから押す
			await page.waitState((st) => st.screen === 'title' && st.buttons?.btn_practice_1, 5000);
			await sleep(500);
			await page.clickButton('btn_practice_1');
			const d = await page.waitState((s) => s.screen === 'duel' && s.duel?.tick > 600, 30000);
			const keys2 = await page.userfsKeys();
			expect(d !== null && keys2.includes(OTHER2), `${name}: (2) 対戦を 5 秒動かしても、別のゲームが書いた /userfs の保存が残る(/userfs の鍵 ${keys2.length} 個)`);

			// (4) v0.2.0 から増えた保存(やさしい設定など)は別のキー。公開中の v0.1.2 のタブが本の保存を自分の形で書いても消えない
			await page.key('Escape');
			await page.waitState((st) => st.screen === 'pause', 3000);
			await page.clickButton('btn_pause_settings');
			await page.waitState((st) => st.screen === 'settings' && st.buttons?.btn_easy_on, 5000);
			await page.clickButton('btn_easy_on');
			const ext = await waitSaved({ saved: () => page.savedExt() }, (v) => v?.settings?.easy === true);
			await page.evaluate(`localStorage.setItem('${SAVE_KEY}', '{"version":1,"fixed":null,"daily":null,"reached_boss":1,"settings":{"volume":75,"shake":true,"reduce_flash":false,"offset_ticks":0}}')`);
			await page.goto(`${base}?debug=1`);
			const t2 = await title();
			const ext2 = await page.savedExt();
			expect(ext?.settings?.easy === true && ext2?.settings?.easy === true && t2 !== null,
				`${name}: (4) v0.1.2 のタブが本の保存を書いた後も、やさしい設定は残る(ext: ${JSON.stringify(ext2?.settings)})`);
			noErrors(page);
		});
	}
}

// 型の練習(v0.2.0): タイトル → 型の練習 → 型を選ぶ(ゆっくり)→ 本物のキーで弾く。体力は減らず、押したずれを数える
async function drill(base) {
	for (const name of browsers()) {
		await withPage(name, `${base}?debug=1`, {}, async (page) => {
			if (!expect(await page.waitState((s) => s.screen === 'title' && s.buttons?.btn_drill, 30000) !== null, `${name}: タイトルに「型の練習」`)) return;
			await page.clickButton('btn_drill');
			const p = await page.waitState((s) => s.screen === 'practice' && s.buttons?.btn_drill_stone_2_b, 5000);
			if (!expect(p !== null && !p.buttons.btn_drill_boss_2, `${name}: 型の練習の画面。着いていない敵 2 は押せない`)) return;
			await page.clickButton('btn_drill_slow');
			await page.clickButton('btn_drill_stone_2_b');
			const s0 = await page.waitState((s) => s.screen === 'duel' && s.duel?.drill_id === 'stone_2_b', 8000);
			if (!expect(s0 !== null && s0.duel.speed === 75, `${name}: 選んだ型をゆっくりで始める(${s0?.duel.drill_id} ${s0?.duel.speed})`)) return;
			const done = new Set();
			const end = Date.now() + 20000;
			let s = s0;
			while (Date.now() < end && (s.duel?.parries ?? 0) < 6) {
				s = await page.state();
				for (const a of s.duel?.attacks ?? []) {
					if (a.kind === 'white' && !done.has(a.id) && s.duel.tick >= a.judged - 4) {
						done.add(a.id);
						await page.key('Space');
					}
				}
				await sleep(8);
			}
			s = await page.state();
			expect(s.duel.parries >= 6 && s.duel.diffs >= 6 && s.duel.player_hp === 5 && !s.duel.over,
				`${name}: 同じ型を繰り返し弾ける。体力は減らず、押したずれを数える(弾いた ${s.duel.parries}、ずれ ${s.duel.diffs}、体力 ${s.duel.player_hp})`);
			await page.shot('drill');
			noErrors(page);
		});
	}
}

// ゲームパッド(v0.2.0)。偽のパッド(lib.mjs の FAKE_PAD)を、Godot がいつも読む navigator.getGamepads() に差し込む。
// 本物のパッドでの手触りは確かめていない(窓なしのブラウザにはパッドが無い)。
async function pad(base) {
	for (const name of browsers()) {
		await withPage(name, `${base}?debug=1`, { pad: true }, async (page) => {
			if (!expect(await page.waitState((s) => s.screen === 'title' && s.buttons?.btn_fixed, 30000) !== null, `${name}: タイトルが出る`)) return;
			await page.padPress(0);
			let s = await page.waitState((st) => st.pad && st.focus === 'btn_fixed', 3000);
			expect(s !== null && s.screen === 'title', `${name}: 最初の A は選ぶだけ(選んだ物: ${s?.focus})`);
			await page.padPress(13);
			s = await page.waitState((st) => st.focus && st.focus !== 'btn_fixed', 3000);
			expect(s !== null, `${name}: 十字キーの下で次のボタンへ(${s?.focus})`);
			await page.padPress(12);
			s = await page.waitState((st) => st.focus === 'btn_fixed', 3000);
			expect(s !== null, `${name}: 十字キーの上で戻る`);
			await page.padPress(0);
			s = await page.waitState((st) => st.screen === 'duel' && st.duel, 5000);
			if (!expect(s !== null, `${name}: A で「いつもの3連戦」が始まる`)) return;
			const done = new Set();
			const end = Date.now() + 25000;
			while (Date.now() < end && (s.duel?.parries ?? 0) < 2) {
				s = await page.state();
				for (const a of s.duel?.attacks ?? []) {
					if (a.kind === 'white' && !done.has(a.id) && s.duel.tick >= a.judged - 6) {
						done.add(a.id);
						await page.padPress(0, 30);
					}
				}
				await sleep(8);
			}
			expect(s.duel.parries >= 2, `${name}: 対戦で A を押すと弾く(弾いた ${s.duel.parries})`);
			expect(s.focus === '', `${name}: 対戦の最中は何も選ばない(${s.focus})`);
			await page.padPress(9);
			s = await page.waitState((st) => st.screen === 'pause', 3000);
			if (!expect(s !== null, `${name}: Start で一時停止`)) return;
			await sleep(300);
			s = await page.waitState((st) => st.focus === 'btn_resume', 3000);
			expect(s !== null, `${name}: 一時停止では「続ける」が選ばれている`);
			await page.padPress(9);
			s = await page.waitState((st) => st.screen === 'duel', 3000);
			expect(s !== null, `${name}: 一時停止で Start を押すと続ける`);
			await page.mouse(5, 5);
			s = await page.waitState((st) => !st.pad, 3000);
			expect(s !== null && s.focus === '', `${name}: マウスを使うと、選んだ印が消える`);
			noErrors(page);
		});
	}
}

// 終わらない連戦(v0.3.0): 本物のキーで 1 体倒す → 合間に倒した数と次の速さ → 2 体目で押すのをやめて負ける →
// 結果に倒した数、記録と実績が保存に届く。取った時の知らせも出る
async function endless(base) {
	for (const name of browsers()) {
		await withPage(name, `${base}?debug=1&go=endless`, {}, async (page) => {
			let s = await page.waitState((st) => st.screen === 'duel' && st.duel?.mode === 4, 30000);
			if (!expect(s !== null, `${name}: 終わらない連戦が始まる`)) return;
			const done = new Set();
			let toast = '';
			const end = Date.now() + 60000;
			while (Date.now() < end) {
				s = await page.state();
				if (s.toast) toast = s.toast;
				if (s.screen !== 'duel') break;
				for (const a of s.duel?.attacks ?? []) {
					if (done.has(a.id)) continue;
					if (a.kind === 'white' && s.duel.tick >= a.judged - 3) { done.add(a.id); await page.key('Space'); }
					else if (a.kind === 'red' && s.duel.tick >= a.judged - 14) { done.add(a.id); await page.key('KeyZ'); }
				}
				if (s.duel?.state === 'STAGGER' && s.duel.tick % 20 === 0) await page.key('Space');
				await sleep(8);
			}
			s = await page.waitState((st) => st.screen === 'interval', 10000);
			if (!expect(s !== null, `${name}: 1 体倒すと合間の画面`)) return;
			await sleep(900);
			await page.shot('endless_interval');
			expect(toast !== '', `${name}: 実績の知らせが出た(${toast})`);
			await page.key('Enter');
			s = await page.waitState((st) => st.screen === 'duel' && st.duel?.boss === 2, 8000);
			expect(s !== null && s.duel.kills === 1, `${name}: 2 体目は敵 2(倒した数 ${s?.duel.kills})`);
			s = await page.waitState((st) => st.screen === 'result', 90000, 250);  // 押さずに負ける
			if (!expect(s !== null, `${name}: 負けると結果の画面(やり直しは出ない)`)) return;
			await sleep(1500);
			await page.shot('endless_result');
			const ext = await page.savedExt();
			expect(ext?.endless?.normal?.kills === 1 && Object.keys(ext?.achievements ?? {}).includes('first_parry'),
				`${name}: 記録と実績が保存に届く(連戦: ${JSON.stringify(ext?.endless?.normal)}、実績: ${Object.keys(ext?.achievements ?? {}).join(' ')})`);
			expect(s.save_failed === false, `${name}: 書けた時に失敗扱いにならない`);
			noErrors(page);
		});
	}
}

// 対戦の教える型(当たっても減らない)の中で、90 ms おきに 110 回押す。押すたびに、ゲームがその押しから描き終わりまでを測る
// how が mouse・touch の時は、右半分を押す(touch はスマホのエミュレーション)
async function latency(base, how) {
	for (const name of browsers()) {
		await withPage(name, `${base}?debug=1&go=duel`, how === 'touch' ? { metrics: MOBILE_1X, touch: true, gpu } : { metrics: PHONE, gpu }, async (page) => {
			const s0 = await duelReady(page);
			if (!expect(s0 !== null, `${name}: 対戦が始まる(${how})`)) return;
			console.log(`    描画: ${s0.renderer}`);
			const press = how === 'key' ? null : await presser(page, how);
			for (let i = 0; i < 110; i++) {
				if (press) await press(true); else await page.key(i % 2 ? 'Space' : 'KeyX');
				await sleep(90);
			}
			const s = await page.state();
			console.log(`    入力を受けたフレームの頭 → 描き終わり: n=${s.lat_godot.n} 中央 ${s.lat_godot.p50} ms / 95% ${s.lat_godot.p95} ms / 最大 ${s.lat_godot.max} ms`);
			console.log(`    ブラウザのイベントの時刻 → 描き終わり: n=${s.lat_js.n} 中央 ${s.lat_js.p50} ms / 95% ${s.lat_js.p95} ms / 最大 ${s.lat_js.max} ms`);
			console.log(`    1 フレーム: 中央 ${s.perf.p50} ms / 95% ${s.perf.p95} ms`);
			console.log(`    届いたイベント: ${s.inputs[s.inputs.length - 1]}`);
			expect(s.lat_js.n >= 100, `${name}: 100 回ぶん測れた`);
			expect(s.lat_js.p95 <= 50, `${name}: ブラウザのイベントから描き終わりまでの 95% 値が 50 ms 以内(R-2)`);
			expect(s.lat_godot.p95 <= 34, `${name}: 入力を受けてから描き終わりまでの 95% 値が 34 ms 以内(NFR-2)`);
			await page.shot('latency');
			noErrors(page);
		});
	}
}

// WebGL が実際に使っている描画の名前(pdState.renderer は、どのブラウザでも「WebKit WebGL」としか出ない)
const GL_NAME = `(() => { const gl = document.createElement('canvas').getContext('webgl2'); const e = gl && gl.getExtension('WEBGL_debug_renderer_info'); return e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : '(分からない)'; })()`;

async function perf(base) {
	for (const name of browsers(['chrome'])) {
		for (const useGpu of [false, true]) {
			await withPage(name, `${base}?debug=1&go=duel&auto=1`, { metrics: PHONE, gpu: useGpu }, async (page) => {
				console.log(`    ${name} ${useGpu ? '--gpu あり' : '--gpu なし'}: ${await page.evaluate(GL_NAME)}`);
				await sleep(PERF_MS);
				const s = await page.state();
				const p = s.perf ?? {};
				expect(p.n >= 1800 && s.duel?.parries >= 10, `${name}: ${PERF_MS / 1000} 秒戦わせて測れた(${p.n} フレーム、弾いた数 ${s.duel?.parries}、敵 ${s.duel?.boss}、screen=${s.screen})`);
				expect(s.duel?.paused !== true, `${name}: 遅いフレーム(0.25 秒超)で勝手に止まっていない`);
				console.log(`    参考値(窓なし・画面の更新に合わせていない・起動直後のフレームも入る): 1 フレーム 中央 ${p.p50} ms / 95% ${p.p95} ms / 最大 ${p.max} ms。NFR-1 の目標は 95% が 16.7 ms 以内 → ${p.p95 <= 16.7 ? '以内' : '超え'}(本物の画面での値は、人が測る)`);
				noErrors(page);
			});
		}
	}
}

async function quiet(base) {
	for (const name of browsers(['chrome'])) {
		await withPage(name, `${base}?debug=1&go=duel&auto=1`, {}, async (page) => {
			if (!expect(await duelReady(page) !== null, `${name}: 対戦が始まる`)) return;
			await sleep(2000);
			const from = Date.now();
			const loaded = page.requests.length;
			let dueling = 0;
			let s = {};
			while (Date.now() - from < QUIET_MS) {
				await sleep(1000);
				s = await page.state();
				if (s.screen === 'duel' && s.duel && !s.duel.over && !s.duel.paused) dueling++;
			}
			const late = page.requests.filter((r) => r.at >= from);
			late.forEach((r) => console.log(`    ${((r.at - from) / 1000).toFixed(1)} 秒: ${r.url}`));
			console.log(`    読み込みの通信 ${loaded} 件。その後の ${QUIET_MS / 1000} 秒のうち、対戦が動いていたのは ${dueling} 秒(最後は screen=${s.screen} 敵 ${s.duel?.boss} 弾いた数 ${s.duel?.parries})`);
			expect(late.length === 0, `${name}: 読み込みの後、${QUIET_MS / 1000} 秒間の通信が 0 件(NFR-8・AC-31)`);
			expect(dueling >= 45, `${name}: その間、対戦が 45 秒以上動いていた(自動の相手は 70 秒ほどで 3 体を倒し切る)`);
			noErrors(page);
		});
	}
}

async function look(base, target) {
	await withPage(browsers(['chrome'])[0], `${base}?debug=1&auto=1&go=${target}`, { metrics: has('--desktop') ? DESKTOP : PHONE, gpu }, async (page) => {
		await page.waitState((s) => s.screen === 'duel' || s.screen === 'calib', 20000);
		for (let i = 0; i < 24; i++) {
			await sleep(600);
			await page.shot(`look_${target}_${String(i).padStart(2, '0')}`);
		}
		const s = await page.state();
		console.log(`    ${JSON.stringify(s.duel ?? s.calib)}`);
		page.errors().forEach((l) => console.log(`    [${l.level}] ${l.text}`));
	});
}

const HOWS = ['key', 'mouse', 'touch'];
const hows = (flag) => (valueOf(flag) ? [valueOf(flag)] : HOWS);
const MODES = {
	'--boot': (b) => boot(b),
	'--keys': (b) => keys(b),
	'--touch2': (b) => touch2(b),
	'--pause': (b) => pause(b),
	'--play': (b) => play(b, hows('--play')),
	'--lose': (b) => lose(b),
	'--flow': (b) => flow(b, hows('--flow')),
	'--settings': (b) => settings(b),
	'--storage': (b) => storage(b),
	'--drill': (b) => drill(b),
	'--pad': (b) => pad(b),
	'--endless': (b) => endless(b),
	'--latency': (b) => latency(b, valueOf('--latency') ?? 'key'),
	'--perf': (b) => perf(b),
	'--quiet': (b) => quiet(b),
	'--shots': (b) => shots(b, withPage, browsers(['chrome'])[0]),
	'--gif': (b) => gif(b, withPage, browsers(['chrome'])[0]),
	'--look': (b) => look(b, valueOf('--look') ?? 'duel'),
};

const picked = Object.keys(MODES).filter((m) => (has('--all') ? m !== '--look' : has(m)));
if (!picked.length) console.log('使い方はファイルの頭を見る');
else {
	const site = serve();
	try {
		for (const mode of picked) {
			const before = failureCount();
			console.log(`==  ${mode}`);
			await MODES[mode](site.url);
			console.log(`${failureCount() === before ? 'OK' : 'NG'}  ${mode}: 失敗 ${failureCount() - before} 件`);
		}
	} finally { site.stop(); }
}
console.log(failureCount() === 0 ? 'ALL OK' : `${failureCount()} 件 NG`);
process.exitCode = failureCount() === 0 ? 0 : 1;
