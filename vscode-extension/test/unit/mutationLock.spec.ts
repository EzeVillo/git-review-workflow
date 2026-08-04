import * as assert from "node:assert";
import { MutationLock } from "../../src/review/mutationLock";

function deferred<T>(): { promise: Promise<T>; resolve: (v: T) => void } {
	let resolve!: (v: T) => void;
	const promise = new Promise<T>((r) => (resolve = r));
	return { promise, resolve };
}

describe("MutationLock", () => {
	it("corre fn y devuelve su resultado cuando no hay nada en vuelo", async () => {
		const lock = new MutationLock();
		const result = await lock.run(async () => 42);
		assert.strictEqual(result, 42);
		assert.strictEqual(lock.isBusy, false);
	});

	it("una segunda llamada concurrente se descarta (undefined), no se encola", async () => {
		const lock = new MutationLock();
		const first = deferred<number>();
		let secondRan = false;

		const p1 = lock.run(async () => {
			return first.promise;
		});
		const p2 = lock.run(async () => {
			secondRan = true;
			return 99;
		});

		assert.strictEqual(lock.isBusy, true);
		first.resolve(1);
		const [r1, r2] = await Promise.all([p1, p2]);

		assert.strictEqual(r1, 1);
		assert.strictEqual(r2, undefined);
		assert.strictEqual(secondRan, false);
	});

	it("el flag busy alterna correctamente", async () => {
		const lock = new MutationLock();
		const seen: boolean[] = [];
		lock.onDidChangeBusy((busy) => seen.push(busy));

		assert.strictEqual(lock.isBusy, false);
		await lock.run(async () => {
			assert.strictEqual(lock.isBusy, true);
		});
		assert.strictEqual(lock.isBusy, false);
		assert.deepStrictEqual(seen, [true, false]);
	});

	it("después de terminar, una nueva llamada corre normalmente", async () => {
		const lock = new MutationLock();
		await lock.run(async () => 1);
		const result = await lock.run(async () => 2);
		assert.strictEqual(result, 2);
	});

	it("una segunda llamada concurrente notifica onDidDiscard con el motivo (FR-036)", async () => {
		const lock = new MutationLock();
		const first = deferred<number>();
		const reasons: string[] = [];
		lock.onDidDiscard((reason) => reasons.push(reason));

		const p1 = lock.run(async () => first.promise);
		const p2 = lock.run(async () => 99);

		const r2 = await p2;
		assert.strictEqual(r2, undefined);
		assert.strictEqual(reasons.length, 1);
		assert.ok(reasons[0].length > 0);

		first.resolve(1);
		await p1;
	});

	it("una llamada que no se descarta no notifica onDidDiscard", async () => {
		const lock = new MutationLock();
		const reasons: string[] = [];
		lock.onDidDiscard((reason) => reasons.push(reason));

		await lock.run(async () => 1);
		await lock.run(async () => 2);

		assert.deepStrictEqual(reasons, []);
	});
});
