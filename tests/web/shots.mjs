// 画面の画像を撮る(--shots)と、README 用の動く画像を作る(--gif)。全部の画像は build/web_shots/、README 用は docs/。
// 場面は、手元の「押す相手」を本物のキーで戦わせて、状態(window.pdState)を見て選ぶ。白黒の版は NFR-11(形で見分けられる)の証拠。
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { DESKTOP, MOBILE, OUT, PHONE, ROOT, expect, inBuild, sleep } from './lib.mjs';
import { fight } from './play.mjs';

const DOCS = path.join(ROOT, 'docs');
const FFMPEG = process.env.FFMPEG || 'ffmpeg'; // PATH に無ければ、環境変数 FFMPEG に実行ファイルの場所を入れる
// README 用の画像は ?band=0 で撮る(計測の帯を描かない。状態の窓口 window.pdState はそのまま)。
// 下の端まで物がある画面(タイトル・設定・タイミング合わせ)は、?debug=1 なしで開き直して撮る
const KEEP = 1;
const GIF_MAX_BYTES = 4e6;
const flying = (d, kind) => d.attacks.some((a) => a.kind === kind && a.judged - d.tick >= 12 && a.judged - d.tick <= 40);

// PNG を、ページの中の canvas で作り直す(白黒にする・上の keep の割合だけ残す)。同じコマの白黒が作れる
async function remake(page, src, dst, { gray = false, keep = 1 } = {}) {
	const b64 = readFileSync(src).toString('base64');
	const out = await page.evaluate(`(async () => {
		const img = new Image();
		img.src = 'data:image/png;base64,${b64}';
		await img.decode();
		const c = document.createElement('canvas');
		c.width = img.width;
		c.height = Math.round(img.height * ${keep});
		const ctx = c.getContext('2d');
		ctx.filter = '${gray ? 'grayscale(1)' : 'none'}';
		ctx.drawImage(img, 0, 0);
		return c.toDataURL('image/png').slice('data:image/png;base64,'.length);
	})()`);
	writeFileSync(dst, Buffer.from(out, 'base64'));
}

// 対戦の場面。来たら 1 回ずつ撮る
const scenes = () => ({
	windup: (s, fresh) => fresh.some((e) => e[1] === 'attack_start'), // 予兆
	white: (s) => !s.duel.teaching && flying(s.duel, 'white'), // 頭が飛んでいる(丸)
	parry: (s, fresh) => fresh.some((e) => e[1] === 'parry'), // 弾いた火花
	stagger: (s) => s.duel.state === 'STAGGER', // よろけ「いま!」
	counter: (s, fresh) => fresh.some((e) => e[1] === 'counter'), // 反撃
	hurt: (s, fresh) => fresh.some((e) => e[1] === 'hurt'), // 当たった
	red: (s) => flying(s.duel, 'red'), // 赤い攻撃(三角)
	// 丸と三角が同時に見える(同梱の型は当たる時刻を 30 tick 以上離しているので、片方は遠くてよい)
	both: (s) => ['red', 'white'].every((k) => s.duel.attacks.some((a) => a.kind === k && a.judged - s.duel.tick >= 12 && a.judged - s.duel.tick <= 100))
		&& (flying(s.duel, 'red') || flying(s.duel, 'white')),
});

// 1 つの対戦を戦いながら、plan に残っている場面を撮る。until(s) まで
async function fightAndSnap(page, plan, snap, until) {
	let wantHurt = 'hurt' in plan;
	return fight(page, 'key', {
		timeoutMs: 150000,
		staggerDelayMs: 500,
		until,
		// 白を 1 つだけ、わざと受ける(教える型の後)
		skip: (a, s) => wantHurt && a.kind === 'white' && !s.duel.teaching && s.duel.player_hp >= 4,
		onState: async (s, fresh) => {
			if (!s.duel || s.screen !== 'duel') return;
			if (fresh.some((e) => e[1] === 'hurt')) wantHurt = false;
			for (const [label, when] of Object.entries(plan)) {
				if (!when(s, fresh)) continue;
				if (label === 'stagger') await sleep(200);
				await snap(label);
				delete plan[label];
				if (label === 'counter') { await sleep(130); await snap('counter_after'); } // 止めが明けた後の、一番派手なコマ
				break; // 1 回の読みで撮るのは 1 枚(押すのが遅れすぎないように)
			}
		},
	});
}

// メニューが無い書き出し用: 敵 3 の練習だけで、対戦の場面を撮る
async function duelOnly(page, taken, snap) {
	const plan = scenes();
	const r = await fightAndSnap(page, plan, snap, (s) => Object.keys(plan).length === 0 || s.duel?.over === true);
	expect(Object.keys(plan).length === 0, `shots: 対戦の場面が全部撮れた(残り: ${Object.keys(plan).join(' ') || '無し'}。受けた数 ${r.state.duel?.hits})`);
}

// 通し: タイトル → 敵 1 → 合間 → 敵 2(一時停止)→ 合間 → 敵 3 → 結果 → コピー。その後、?debug=1 なしで開き直して タイトル・設定・タイミング合わせ
async function fullRun(page, base, taken, snap) {
	const title = await page.waitState((s) => s.screen === 'title' && s.buttons?.btn_settings, 30000);
	if (!expect(title !== null, 'shots: タイトルが出る')) return;
	// 後で ?debug=1 なしで押す場所を、今のうちに覚える(並びは同じ)
	const at = { settings: await page.toCss(title, ...title.buttons.btn_settings), drill: await page.toCss(title, ...title.buttons.btn_drill), ach: await page.toCss(title, ...title.buttons.btn_achievements) };
	await page.clickButton('btn_settings');
	const set = await page.waitState((s) => s.screen === 'settings' && s.buttons?.btn_calib, 5000);
	if (!expect(set !== null, 'shots: 設定が開く')) return;
	at.calib = await page.toCss(set, ...set.buttons.btn_calib);
	await page.clickButton('btn_back');
	await page.waitState((s) => s.screen === 'title', 5000);
	await page.key('Enter');

	const plan = scenes();
	for (let boss = 1; boss <= 3; boss++) {
		if (!expect(await page.waitState((s) => s.screen === 'duel' && s.duel?.boss === boss, 8000) !== null, `shots: 敵 ${boss} の対戦が始まる`)) return;
		if (boss === 2) { // 一時停止。最初の型が見えている所で止める
			await page.waitState((s) => s.duel.attacks.length > 0, 8000);
			await sleep(500);
			await page.clickButton('btn_pause');
			await page.waitState((s) => s.duel?.paused && s.buttons?.btn_resume, 3000);
			await sleep(500);
			await snap('pause');
			await page.clickButton('btn_resume');
		}
		const r = await fightAndSnap(page, plan, snap, (s) => s.screen === 'interval' || s.screen === 'result' || Boolean(s.buttons?.btn_retry));
		const want = boss < 3 ? 'interval' : 'result';
		if (!expect(r.state.screen === want, `shots: 敵 ${boss} を倒して ${want} の画面になる(今は ${r.state.screen}、受けた数 ${r.state.duel?.hits})`)) return;
		await sleep(1200);
		await snap(boss < 3 ? `interval_${boss}` : 'result');
		if (boss < 3) await page.key('Enter');
	}
	expect(Object.keys(plan).length === 0, `shots: 対戦の場面が全部撮れた(残り: ${Object.keys(plan).join(' ') || '無し'})`);
	await page.clickButton('btn_copy');
	await sleep(400);
	await snap('result_copied');

	// ?debug=1 なし(デバッグ用の帯が出ない)。同じプロフィールなので、タイトルに記録の行が出る
	await page.goto(base);
	await page.evaluate('1'); // 起動の間は返ってこない
	await sleep(3200); // 頭が線へ飛んでいる所
	await snap('title');
	await page.mouse(...at.settings);
	await sleep(800);
	await snap('settings');
	await page.mouse(...at.calib);
	await sleep(2600);
	await snap('calib');
	// 型の練習の画面(3 体を倒した後なので、敵 3 まで選べる)
	await page.goto(base);
	await page.evaluate('1');
	await sleep(1500);
	await page.mouse(...at.drill);
	await sleep(800);
	await snap('practice');
	// 実績の一覧(3 体を倒したので、いくつか取れている)
	await page.goto(base);
	await page.evaluate('1');
	await sleep(1500);
	await page.mouse(...at.ach);
	await sleep(800);
	await snap('achievements');
	for (const label of ['title', 'settings', 'calib', 'practice', 'achievements']) copyFileSync(taken[label], path.join(DOCS, `${label}.png`));
	for (const [label, file] of [['pause', 'pause'], ['interval_1', 'interval'], ['result_copied', 'result']]) await remake(page, taken[label], path.join(DOCS, `${file}.png`), { keep: KEEP });
}

export async function shots(base, withPage, name) {
	mkdirSync(DOCS, { recursive: true });
	const menus = inBuild('ui/title.gd');
	await withPage(name, `${base}?debug=1&band=0${menus ? '' : '&go=duel3'}`, { metrics: PHONE }, async (page) => {
		const taken = {};
		const snap = async (label) => { taken[label] = await page.shot(`shot_${label}`); };
		if (menus) await fullRun(page, base, taken, snap); else await duelOnly(page, taken, snap);
		for (const label of Object.keys(scenes())) if (taken[label]) await remake(page, taken[label], taken[label].replace(/\.png$/, '_gray.png'), { gray: true });
		// README 用(帯は ?band=0 で出ていない)
		const main = taken.both ?? taken.red;
		if (main) {
			await remake(page, main, path.join(DOCS, 'duel.png'), { keep: KEEP });
			await remake(page, main, path.join(DOCS, 'duel_gray.png'), { keep: KEEP, gray: true });
		}
		if (taken.parry) await remake(page, taken.parry, path.join(DOCS, 'parry.png'), { keep: KEEP });
		if (taken.stagger) await remake(page, taken.stagger, path.join(DOCS, 'stagger.png'), { keep: KEEP });
		console.log(`    撮った場面: ${Object.keys(taken).join(' ')}(対戦の場面は、白黒の版 _gray も)`);
	});
	// 横長と、スマホ(3 倍密度。縦と横)。自動の相手に戦わせて、頭が飛んでいる所を撮る
	for (const [label, metrics, touch] of [['desktop', DESKTOP, false], ['mobile', MOBILE, true], ['mobile_landscape', { ...MOBILE, width: MOBILE.height, height: MOBILE.width }, true]]) {
		await withPage(name, `${base}?debug=1&auto=1&go=duel3`, { metrics, touch }, async (page) => {
			const s = await page.waitState((st) => st.duel && !st.duel.teaching && flying(st.duel, 'white'), 60000);
			await page.shot(`shot_${label}`);
			const now = await page.state();
			expect(s !== null, `shots: ${label}(${metrics.width}×${metrics.height})で対戦が撮れた(ビューポート ${now.vp}、720×1280 の左上 ${now.stage})`);
			expect(now.duel?.paused !== true, `shots: ${label} で、遅いフレーム(0.25 秒超)で勝手に止まっていない(1 フレーム 95% ${now.perf?.p95} ms)`);
		});
	}
	// タイミング合わせ: 8 回を本物のキーで押して、結果まで
	await withPage(name, `${base}?debug=1&go=calib`, { metrics: PHONE }, async (page) => {
		const s0 = await page.waitState((s) => s.screen === 'calib' && s.calib, 20000);
		if (!expect(s0 !== null, 'shots: タイミング合わせの画面が出る')) return;
		await sleep(1200);
		await page.shot('shot_calib_debug');
		const pressed = new Set();
		const end = Date.now() + 30000;
		let s = s0;
		while (Date.now() < end && !s.calib?.done) {
			s = await page.state();
			const next = (s.calib?.contacts ?? []).find((t) => !pressed.has(t) && s.calib.tick >= t - 2);
			if (next !== undefined) { pressed.add(next); await page.key('Space'); }
		}
		await sleep(600);
		await page.shot('shot_calib_done');
		s = await page.state();
		console.log(`    タイミング合わせ: 押した ${pressed.size} 回、差 ${JSON.stringify(s.calib?.diffs)}(tick)、ボタン: ${Object.keys(s.buttons).join(' ')}`);
		expect(s.calib?.done === true, 'shots: タイミング合わせが 8 回で終わる');
	});
}

// README 用の動く画像: 敵 1 を、教える型 → 弾く → よろけ → 反撃 まで。コマは Page.startScreencast、各コマの長さは timestamp の差
export async function gif(base, withPage, name) {
	if (spawnSync(FFMPEG, ['-version'], { encoding: 'utf8' }).status !== 0) {
		console.log('--  --gif: ffmpeg が無いので飛ばす(PATH に入れるか、環境変数 FFMPEG に場所を入れる)');
		return;
	}
	const dir = path.join(OUT, 'gif_frames');
	const out = path.join(DOCS, 'play.gif');
	await withPage(name, `${base}?debug=1&go=duel`, { metrics: PHONE }, async (page) => {
		rmSync(dir, { recursive: true, force: true });
		mkdirSync(dir, { recursive: true });
		mkdirSync(DOCS, { recursive: true });
		const frames = [];
		await page.waitState((s) => s.duel, 20000); // 読み込み中の画面を録らない
		page.cdp.onEvent((msg) => {
			if (msg.method !== 'Page.screencastFrame') return;
			const file = `f${String(frames.length).padStart(5, '0')}.jpg`;
			writeFileSync(path.join(dir, file), Buffer.from(msg.params.data, 'base64'));
			frames.push({ file, t: msg.params.metadata.timestamp });
			page.cdp.send('Page.screencastFrameAck', { sessionId: msg.params.sessionId }).catch(() => { /* 閉じた後 */ });
		});
		await page.cdp.send('Page.startScreencast', { format: 'jpeg', quality: 90, maxWidth: PHONE.width, maxHeight: PHONE.height, everyNthFrame: 1 });
		let counterAt = 0;
		await fight(page, 'key', {
			timeoutMs: 40000,
			staggerDelayMs: 450,
			onState: (s, fresh) => { if (!counterAt && fresh.some((e) => e[1] === 'counter')) counterAt = Date.now(); },
			until: () => counterAt > 0 && Date.now() - counterAt > 1300,
		});
		await page.cdp.send('Page.stopScreencast');
		await sleep(300); // 最後のコマが届くまで
		if (!expect(counterAt > 0 && frames.length >= 20, `gif: 反撃までが録れた(${frames.length} コマ、${frames.length ? (frames.at(-1).t - frames[0].t).toFixed(1) : 0} 秒)`)) return;
		// 最後のコマの duration は concat が使わない。終わりの止まりは、録る側の待ちで作っている
		const lines = frames.slice(0, -1).flatMap((f, i) => [`file '${f.file}'`, `duration ${(frames[i + 1].t - f.t).toFixed(3)}`]);
		lines.push(`file '${frames.at(-1).file}'`);
		const list = path.join(dir, 'list.txt');
		writeFileSync(list, `${lines.join('\n')}\n`);
		// 4 MB を超えたら、コマ数・幅・色数を落として作り直す
		for (const [fps, width, colors] of [[15, 360, 128], [12, 360, 96], [10, 320, 64], [8, 300, 48]]) {
			const vf = `crop=iw:ih*${KEEP}:0:0,fps=${fps},scale=${width}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${colors}:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle`;
			const r = spawnSync(FFMPEG, ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-vf', vf, '-loop', '0', out], { encoding: 'utf8' });
			if (!expect(r.status === 0, `gif: ffmpeg(${fps} fps・幅 ${width}・${colors} 色)`)) { console.log(r.error?.message ?? r.stderr); return; }
			const size = statSync(out).size;
			console.log(`    docs/play.gif: ${(size / 1e6).toFixed(2)} MB(${fps} fps・幅 ${width}・${colors} 色)`);
			if (size <= GIF_MAX_BYTES) { rmSync(dir, { recursive: true, force: true }); return; }
		}
		expect(false, 'gif: 4 MB 以下に収まった');
	});
}
