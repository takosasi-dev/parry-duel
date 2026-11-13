// 手元の「押す相手」。window.pdState の攻撃の当たる tick を読み、本物のキー・マウス・タッチを CDP で送って戦う(AC-27・AC-28)。
// ゲームの中の自動の相手(?auto=1)とは別物で、入力はブラウザのイベントとして届く。
import { readFileSync } from 'node:fs';
import { expect, inBuild, sleep } from './lib.mjs';

export const PARRY_TYPES = ['parry', 'parry_whiff', 'parry_red', 'counter']; // 弾く を使った時に出る出来事
const WHITE_LEAD = 2; // 白は、当たる tick のこの数だけ前から押す
const RED_LEAD = 14; // 赤は、この数だけ前から避ける(避けるは 30 tick 続く)
const INPUT_CLASS = { key: 'InputEventKey', mouse: 'InputEventMouseButton', touch: 'InputEventScreenTouch' };

// duel.events は直近 24 個だけなので、通し番号で「前に読んだ後の分」だけを数える。tally = { seq, counts }
export function take(s, tally) {
	const fresh = (s.duel?.events ?? []).filter((e) => e[0] > tally.seq);
	for (const e of fresh) tally.counts[e[1]] = (tally.counts[e[1]] ?? 0) + 1;
	if (fresh.length) tally.seq = fresh[fresh.length - 1][0];
	return fresh;
}
export const newTally = () => ({ seq: 0, counts: {} });
export const count = (tally, types) => types.reduce((n, t) => n + (tally.counts[t] ?? 0), 0);

// 弾く・避けるを 1 回送る関数を作る。押す場所は、右半分・左半分の真ん中あたり(ゲームの座標)
export async function presser(page, how) {
	const s = await page.waitState((st) => st.vp && st.stage, 20000);
	const right = await page.gameCss(s, 540, 760);
	const left = await page.gameCss(s, 180, 760);
	if (how === 'key') return (parry) => page.key(parry ? 'Space' : 'KeyZ');
	if (how === 'touch') return (parry) => page.touch([parry ? right : left]);
	return (parry) => page.mouse(...(parry ? right : left));
}

// 対戦を 1 つ戦う。until(s) が真になるか、時間切れまで。
//   skip(attack, s): 真を返した攻撃は押さない(わざと当たる時に使う)
//   staggerDelayMs: よろけてから反撃するまでの待ち(「いま!」を撮る時に使う)
//   onState(s, fresh): 状態を読むたびに呼ぶ(fresh は新しい出来事)
export async function fight(page, how, { until, tally = newTally(), timeoutMs = 240000, skip = null, staggerDelayMs = 0, onState = null } = {}) {
	const press = await presser(page, how);
	const done = new Set();
	const end = Date.now() + timeoutMs;
	let staggerSince = 0;
	let counterAt = 0;
	let s = {};
	while (Date.now() < end) {
		s = await page.state();
		const fresh = take(s, tally);
		if (onState) await onState(s, fresh);
		if (until(s)) return { state: s, tally, timedOut: false };
		const d = s.duel;
		if (!d || s.screen !== 'duel' || d.paused || d.over || d.state === 'WAIT_NEXT' || d.resume_left > 0) { await sleep(20); continue; }
		if (d.state === 'STAGGER') {
			staggerSince ||= Date.now();
			// 反撃は 1 回だけ押す。硬直で捨てられた時のために、0.25 秒たってもよろけたままなら押し直す
			if (d.lock <= 2 && Date.now() - staggerSince >= staggerDelayMs && Date.now() - counterAt > 250) {
				counterAt = Date.now();
				await press(true);
			}
			continue;
		}
		staggerSince = 0;
		for (const a of d.attacks) {
			if (done.has(a.id)) continue;
			if (skip && skip(a, s)) { done.add(a.id); continue; }
			const free = d.lock <= 2; // 押しが届く頃(1〜2 フレーム後)には硬直が明けている
			if (a.kind === 'white' && d.tick >= a.judged - WHITE_LEAD && (free || d.tick >= a.judged + 8)) { done.add(a.id); await press(true); break; }
			if (a.kind === 'red' && d.tick >= a.judged - RED_LEAD && (free || d.tick >= a.judged - 2)) { done.add(a.id); await press(false); break; }
		}
	}
	return { state: s, tally, timedOut: true };
}

const report = (label, r) => {
	const d = r.state.duel ?? {};
	const c = r.tally.counts;
	console.log(`    ${label}: 受けた数 ${d.hits} / 弾いた数 ${d.parries}(ぴったり ${d.justs})/ 空振り ${c.parry_whiff ?? 0} / 赤を弾こうとした ${c.parry_red ?? 0} / 避けた ${c.dodge_avoid ?? 0} / 反撃 ${c.counter ?? 0} / 時間 ${d.tick} tick`);
};

// --play: 敵 3 だけの練習(赤・ため・白が全部出る)を、本物の入力で倒し切る
export async function playPractice(page, how) {
	const n = page.name;
	const first = await page.waitState((s) => s.duel, 20000);
	const r = await fight(page, how, { until: (s) => s.duel?.over === true });
	const d = r.state.duel ?? {};
	report(`${n} ${how}`, r);
	console.log(`    届いたイベント: ${(r.state.inputs ?? []).at(-1)}`);
	// 効果音(仮の Sfx の間は sfx が −1)。聞こえるかは、消音なので確かめられない。再生が呼ばれた回数だけを見る
	if (r.state.sfx >= 0) expect(first?.sfx === 0 && r.state.sfx > 0, `${n} ${how}: 効果音は、最初の入力の前は鳴らさず(${first?.sfx} 回)、その後は鳴らしている(${r.state.sfx} 回)(FR-29)`);
	expect(!r.timedOut && d.over && d.won, `${n} ${how}: 敵 3 を倒し切る(over=${d.over} won=${d.won} 体力 ${d.player_hp})`);
	expect((r.state.inputs ?? []).some((t) => t.startsWith(INPUT_CLASS[how])), `${n} ${how}: 入力が ${INPUT_CLASS[how]} として届いている`);
	expect((r.tally.counts.counter ?? 0) === 3, `${n} ${how}: 反撃が 3 回(段階 3 つ)`);
	return r;
}

// --lose: 負けて「この敵からやり直す」(E-13・NFR-6)。教える型だけ成功して、後は押さない
export async function playLose(page) {
	const n = page.name;
	const tally = newTally();
	const lose = () => fight(page, 'key', { tally, timeoutMs: 90000, skip: (a, s) => !s.duel.teaching, until: (s) => Boolean(s.buttons?.btn_retry) });
	let r = await lose();
	let d = r.state.duel ?? {};
	if (!expect(!r.timedOut && d.over && !d.won && d.hits === 5, `${n}: 押さないと 5 回受けて負け、やり直しのボタンが出る(受けた数 ${d.hits}、ボタン: ${Object.keys(r.state.buttons ?? {}).join(' ')})`)) return;
	expect(Boolean(r.state.buttons.btn_lose_title) && !r.state.buttons.btn_pause, `${n}: 負けた画面に「タイトルへ」があり、一時停止ボタンは消えている`);
	await page.shot('lose');
	const lostTicks = d.tick;
	for (const [how, press] of [['R キー', () => page.key('KeyR')], ['ボタン', () => page.clickButton('btn_retry')]]) {
		const before = r.state.duel;
		const t0 = Date.now();
		await press();
		const s = await page.waitState((st) => st.duel && !st.duel.over && st.duel.state === 'INTRO', 5000);
		const ms = Date.now() - t0;
		d = s?.duel ?? {};
		expect(s !== null && ms <= 500, `${n}: ${how}でやり直すと、0.5 秒以内に敵の構えが始まる(${ms} ms)(NFR-6)`);
		expect(d.retries === before.retries + 1 && d.hits === before.hits && d.player_hp === 5 && d.boss === before.boss && d.phase === 1 && d.teaching === false,
			`${n}: やり直しは、段階 1・体力 5・受けた数は引き継ぎ・やり直し +1・教える型は飛ばす(受けた数 ${d.hits}、やり直し ${d.retries}、体力 ${d.player_hp}、段階 ${d.phase}、教える型 ${d.teaching})(E-13)`);
		r = await lose();
		if (!expect(!r.timedOut && r.state.duel.hits === before.hits + 5, `${n}: もう一度負ける(受けた数 ${r.state.duel?.hits})`)) return;
	}
	console.log(`    1 回目に負けた時の時間 ${lostTicks} tick。最後の状態: 受けた数 ${r.state.duel.hits}、やり直し ${r.state.duel.retries}`);
	await page.clickButton('btn_lose_title');
	const t = await page.waitState((s) => s.screen === 'title', 3000);
	expect(t !== null, `${n}: 「タイトルへ」でタイトルに戻る(screen=${(await page.state()).screen})`);
}

// --flow: タイトル → 対戦 → 合間 → 対戦 → 合間 → 対戦 → 結果(AC-27・AC-28)。メニューの画面(ui/title.gd ほか)が合流してから動く
export const hasMenus = () => ['title', 'interval', 'result'].every((f) => inBuild(`ui/${f}.gd`));
// daily を真にすると、入口が「今日の3連戦」になる(キーの割り当てが無いので、入口だけはボタンで押す)
export async function playFlow(page, how, url, daily = false) {
	const n = `${page.name} ${how}${daily ? '(今日の3連戦)' : ''}`;
	const go = async (button) => (how === 'key' ? (await page.key('Enter'), true) : page.clickButton(button, how));
	const point = how === 'touch' ? 'touch' : 'mouse'; // キーの割り当てが無いボタン(コピー・タイトルへ)を押す手段
	const record = (v) => (daily ? v?.daily?.best : v?.fixed);
	const title = await page.waitState((s) => s.screen === 'title' && s.buttons?.btn_fixed, 20000);
	if (!expect(title !== null, `${n}: タイトルに「いつもの3連戦」のボタンが出る`)) return;
	expect(!title.buttons.btn_practice_2 && await page.saved() === null, `${n}: 初めは保存が無く、練習は敵 1 だけ押せる(押せるボタン: ${Object.keys(title.buttons).join(' ')})`);
	if (daily) await page.clickButton('btn_daily', point); else await go('btn_fixed');
	const tally = newTally();
	let retries = 0;
	for (let boss = 1; boss <= 3; boss++) {
		if (!expect(await page.waitState((s) => s.screen === 'duel' && s.duel?.boss === boss, 8000) !== null, `${n}: 敵 ${boss} の対戦が始まる`)) return;
		let r;
		for (;;) {
			r = await fight(page, how, { tally, until: (s) => s.screen === 'interval' || s.screen === 'result' || Boolean(s.buttons?.btn_retry) });
			if (r.timedOut || !r.state.buttons?.btn_retry || retries >= 5) break;
			retries++; // 負けた。「この敵からやり直す」
			if (how === 'key') await page.key('KeyR'); else await page.clickButton('btn_retry', how);
			await page.waitState((s) => s.duel && !s.duel.over, 8000);
		}
		report(`${n} 敵 ${boss}`, r);
		const want = boss < 3 ? 'interval' : 'result';
		if (!expect(r.state.screen === want, `${n}: 敵 ${boss} を倒すと ${want} の画面になる(今は ${r.state.screen})`)) return;
		if (boss < 3) {
			await sleep(700); // 「次の敵へ」は、画面に入って 500 ms 後から押せる
			await go('btn_next');
		}
	}
	const s = await page.waitState((st) => st.screen === 'result' && st.buttons?.btn_again, 8000);
	expect(s !== null, `${n}: 結果の画面に「もう1回」が出る`);
	if (!expect(s !== null && s.duel?.won === true, `${n}: 勝ちで終わる(やり直し ${retries} 回)`)) return;
	const d = s.duel;
	await sleep(1500); // 入る時の動きが終わるまで
	await page.shot(`flow_${how}_result`);

	// 記録が、ブラウザの中の保存(IndexedDB)に届いている。時間は、やり直しが無ければ対戦の tick と同じ
	const saved = await waitSaved(page, record);
	const f = record(saved) ?? {};
	expect(f.hits === d.hits && (daily || (f.justs === d.justs && f.retries === d.retries)) && (retries > 0 || f.ticks === d.tick) && saved?.reached_boss === 3,
		`${n}: 記録が保存に届いた(保存: ${JSON.stringify(daily ? saved?.daily : saved?.fixed)} 着いた敵 ${saved?.reached_boss} / 対戦: 受けた数 ${d.hits} 時間 ${d.tick} tick ぴったり ${d.justs})`);

	// 「コピー」: クリップボードに §9.12 の 3 行が入り、枠の下に「コピーを試した…」の行が出る
	await page.cdp.send('Browser.grantPermissions', { permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] });
	const [, cy] = s.buttons.btn_copy; // ボタンの中心。知らせの行は、その 88〜56 px 上(ui/result.gd の並び)
	const rowAt = await page.toCss(s, s.stage[0] + 40, cy - 90);
	const k = rowAt[0] / (s.stage[0] + 40);
	const row = [rowAt[0], rowAt[1], 640 * k, 38 * k];
	const before = readFileSync(await page.shot(`flow_${how}_row_before`, row));
	expect(await page.clickButton('btn_copy', point), `${n}: 「コピー」が押せる`);
	await sleep(400);
	const after = readFileSync(await page.shot(`flow_${how}_row_after`, row));
	expect(!before.equals(after), `${n}: 「コピー」を押すと、枠の下に知らせの行が出る(画像 flow_${how}_row_before / _after)`);
	// Windows のクリップボードは、改行を CRLF にして返す(ブラウザに LF で書いても同じ)。なので CR は落として比べる
	const clip = String(await page.evaluate('navigator.clipboard.readText().catch((e) => "読めない: " + e.message)')).split(/\r?\n/);
	const sec = Math.floor(f.ticks * 10 / 120);
	const want2 = `受けた数 ${d.hits}${d.hits === 0 ? '(無傷)' : ''} / ${Math.floor(sec / 10)}.${sec % 10}秒 / ぴったり ${d.justs} / やり直し ${d.retries}`;
	const label = daily ? '今日の3連戦・1回目' : 'いつもの3連戦';
	expect(clip.length === 3 && new RegExp(`^\\S+ \\d{4}-\\d\\d-\\d\\d\\(${label}\\)$`).test(clip[0]) && clip[1] === want2 && clip[2] === 'https://takosasi-dev.github.io/parry-duel/',
		`${n}: クリップボードに共有する文字の 3 行が入った: ${JSON.stringify(clip)}`);
	await page.shot(`flow_${how}_copied`);

	// タイトルへ戻ると、記録の行が出て、練習の敵 2・3 が押せる。読み込み直しても残る
	expect(await page.clickButton('btn_title', point), `${n}: 「タイトルへ」が押せる`);
	const back = await page.waitState((st) => st.screen === 'title' && st.buttons?.btn_fixed, 5000);
	expect(back !== null && Boolean(back.buttons.btn_practice_3), `${n}: タイトルに戻ると、練習の敵 3 まで押せる(押せるボタン: ${Object.keys(back?.buttons ?? {}).join(' ')})`);
	await sleep(600);
	await page.shot(`flow_${how}_title_after`);
	await page.goto(url);
	const again = await page.waitState((st) => st.screen === 'title' && st.buttons?.btn_fixed, 30000);
	const kept = await page.saved();
	expect(again !== null && Boolean(again.buttons.btn_practice_3) && JSON.stringify(record(kept)) === JSON.stringify(record(saved)),
		`${n}: 読み込み直しても記録が残っている(保存: ${JSON.stringify(record(kept))}、練習の敵 3 が押せる: ${Boolean(again?.buttons.btn_practice_3)})`);
	await sleep(600);
	await page.shot(`flow_${how}${daily ? '_daily' : ''}_title_reloaded`);
}

// 保存が pred を満たすまで待つ(書いてから IndexedDB に届くまで、少し間がある)。満たさなければ最後に読んだ物
export async function waitSaved(page, pred, timeoutMs = 3000) {
	const end = Date.now() + timeoutMs;
	let v = null;
	do {
		v = await page.saved();
		if (pred(v)) return v;
		await sleep(50);
	} while (Date.now() < end);
	return v;
}
