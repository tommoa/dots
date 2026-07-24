import { describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	TERMINAL_BENCH_SOURCE,
	benchmarkCapabilityScores,
	blendCapabilityScore,
	execute,
	normalizeDeepSwe,
	normalizeTerminalBench,
	percentileRanks,
	renderRegions,
	replaceGeneratedRegions,
	staleRegions,
	type BenchmarkSnapshot,
	type RegionName,
	type TerminalBenchSnapshot,
	regionNames,
} from "./generator";
import { models, taskTypes } from "./policy";

function rawRow(model: string, effort: string | null, overrides: Record<string, unknown> = {}) {
	return {
		model,
		harness: "mini-swe-agent",
		reasoning_effort: effort,
		source: "deep-swe",
		pass_at_1: 0.5,
		mean_cost_usd: 2,
		mean_input_tokens: 1000,
		mean_output_tokens: 100,
		mean_agent_steps: 10,
		n_tasks_attempted: 113,
		n_runs: 4,
		...overrides,
	};
}

function rawPayload(rows: unknown[]) {
	return {
		scope: "Every DeepSWE rollout grouped by configuration",
		unit: "pass@1 is attempt pass rate",
		n_tasks_in_set: 113,
		rows,
	};
}

function snapshot(rows: BenchmarkSnapshot["rows"]): BenchmarkSnapshot {
	return {
		schemaVersion: 1,
		benchmark: "DeepSWE v1.1",
		source: "https://deepswe.datacurve.ai/artifacts/v1.1/leaderboard-live.json",
		taskCount: 113,
		rows,
	};
}

function terminalSnapshot(rows: TerminalBenchSnapshot["rows"]): TerminalBenchSnapshot {
	return {
		schemaVersion: 1,
		benchmark: "Terminal-Bench 2.1",
		source: "https://api.github.com/repos/harbor-framework/terminal-bench-2-1/contents/leaderboard/submissions?ref=main",
		license: "Apache-2.0",
		rows,
	};
}

function terminalRow(sourceModel: string, accuracy: number, canonicalModel?: string) {
	return {
		sourceFile: `${sourceModel}-${accuracy}.json`,
		sourceModel,
		...(canonicalModel ? { canonicalModel } : {}),
		effort: "max",
		agent: "agent",
		date: "2026-07-01",
		accuracy,
		trialCount: 100,
		rewardHackPercent: 0,
	};
}

function terminalPayload(model = "openai/gpt-5.6-terra") {
	return {
		source_filter: {
			agent: "codex",
			model_name: model,
			reasoning_effort: "max",
		},
		metadata: { date: "2026-07-11", reasoning_effort: "max" },
		metrics: { accuracy: 78.43, n_trials: 445, reward_hacks: 0.22 },
	};
}

function context(overrides: Partial<Record<RegionName, string>> = {}) {
	return [
		"before",
		...regionNames.flatMap((name) => [`<!-- BEGIN GENERATED: ${name} -->`, overrides[name] ?? "old", `<!-- END GENERATED: ${name} -->`, `prose after ${name}`]),
		"after",
		"",
	].join("\n");
}

describe("reviewed model policy", () => {
	test("has complete bounded scores and unique identities", () => {
		const ids = new Set<string>();
		const aliases = new Set<string>();
		for (const model of models) {
			expect(ids.has(model.id)).toBeFalse();
			ids.add(model.id);
			for (const alias of model.benchmarkAliases) {
				expect(aliases.has(alias)).toBeFalse();
				aliases.add(alias);
			}
			for (const task of taskTypes) expect(model.capabilities[task]).toBeWithin(0, 6);
			expect(model.cost).toBeWithin(1, 6);
			expect(model.speed).toBeWithin(1, 6);
		}
		expect(ids.size).toBe(7);
	});

	test("makes all reviewed models work-eligible and discounts every work GPT", () => {
		expect(models.every((model) => model.profiles.work.eligible)).toBeTrue();
		const workGpts = models.filter((model) => model.id.startsWith("gpt-") && model.profiles.work.eligible);
		expect(workGpts.map((model) => model.id)).toEqual(["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]);
		expect(workGpts.every((model) => model.workPriceMultiplier === 0.5)).toBeTrue();
	});

	test("keeps GPT-5.5 out of the personal table", () => {
		expect(models.find((model) => model.id === "gpt-5.5")?.profiles.personal.eligible).toBeFalse();
	});
});

describe("DeepSWE normalization", () => {
	test("maps reviewed aliases and preserves unknown reference models", () => {
		const result = normalizeDeepSwe(rawPayload([rawRow("new-model", null), rawRow("gpt-5-6-sol", "high")]));
		expect(result.rows).toEqual([
			{
				sourceModel: "gpt-5-6-sol",
				canonicalModel: "gpt-5.6-sol",
				effort: "high",
				passAt1: 0.5,
				meanCostUsd: 2,
				meanInputTokens: 1000,
				meanOutputTokens: 100,
				meanAgentSteps: 10,
				taskCount: 113,
				runCount: 4,
			},
			{
				sourceModel: "new-model",
				effort: "default",
				passAt1: 0.5,
				meanCostUsd: 2,
				meanInputTokens: 1000,
				meanOutputTokens: 100,
				meanAgentSteps: 10,
				taskCount: 113,
				runCount: 4,
			},
		]);
	});

	test("sorts effort variants canonically", () => {
		const result = normalizeDeepSwe(rawPayload([rawRow("gpt-5-6-sol", "max"), rawRow("gpt-5-6-sol", "low"), rawRow("gpt-5-6-sol", "xhigh")]));
		expect(result.rows.map((row) => row.effort)).toEqual(["low", "xhigh", "max"]);
	});

	test("rejects duplicate configurations", () => {
		expect(() => normalizeDeepSwe(rawPayload([rawRow("gpt-5-6-sol", "high"), rawRow("gpt-5-6-sol", "high")]))).toThrow("Duplicate DeepSWE configuration");
	});

	test("rejects invalid units and numeric ranges", () => {
		expect(() => normalizeDeepSwe({ ...rawPayload([]), unit: "score" })).toThrow("Unexpected DeepSWE unit");
		expect(() => normalizeDeepSwe(rawPayload([rawRow("gpt-5-6-sol", "high", { pass_at_1: 2 })]))).toThrow("must be between 0 and 1");
		expect(() => normalizeDeepSwe(rawPayload([rawRow("gpt-5-6-sol", "high", { mean_cost_usd: -1 })]))).toThrow("must not be negative");
	});
});

describe("Terminal-Bench normalization", () => {
	test("normalizes provider-prefixed reviewed models", () => {
		const result = normalizeTerminalBench([
			{
				sourceFile: "submission.json",
				payload: terminalPayload(),
			},
		]);
		expect(result.rows[0]).toEqual({
			sourceFile: "submission.json",
			sourceModel: "gpt-5.6-terra",
			canonicalModel: "gpt-5.6-terra",
			effort: "max",
			agent: "codex",
			date: "2026-07-11",
			accuracy: 78.43,
			trialCount: 445,
			rewardHackPercent: 0.22,
		});
	});

	test("rejects duplicate files and invalid accuracy", () => {
		const payload = {
			source_filter: { agent: "agent", model_name: "model", reasoning_effort: "high" },
			metadata: { date: "2026-07-01", reasoning_effort: "high" },
			metrics: { accuracy: 50, n_trials: 100, reward_hacks: 0 },
		};
		expect(() => normalizeTerminalBench([{ sourceFile: "same.json", payload }, { sourceFile: "same.json", payload }])).toThrow("Invalid or duplicate");
		expect(() => normalizeTerminalBench([{ sourceFile: "bad.json", payload: { ...payload, metrics: { ...payload.metrics, accuracy: 101 } } }])).toThrow("between 0 and 100");
	});
});

describe("refresh command", () => {
	test("updates snapshots without reading or generating context", async () => {
		const directory = await mkdtemp(join(tmpdir(), "model-routing-"));
		const deepSwePath = join(directory, "deepswe.json");
		const terminalPath = join(directory, "terminal.json");
		const missingContextPath = join(directory, "context.md");
		const deepSweUrl = "https://benchmark.example/deepswe.json";
		const terminalSubmissionUrl = "https://benchmark.example/terminal.json";
		const originalFetch = globalThis.fetch;
		globalThis.fetch = (async (input) => {
			const url = String(input);
			if (url === deepSweUrl) return Response.json(rawPayload([rawRow("gpt-5-6-sol", "max")]));
			if (url === TERMINAL_BENCH_SOURCE) return Response.json([{ name: "terminal.json", type: "file", download_url: terminalSubmissionUrl }]);
			if (url === terminalSubmissionUrl) return Response.json(terminalPayload("new-model"));
			return new Response("not found", { status: 404 });
		}) as typeof fetch;

		try {
			await execute({
				command: "refresh",
				contextPath: missingContextPath,
				snapshotPath: deepSwePath,
				terminalSnapshotPath: terminalPath,
				source: deepSweUrl,
			});
			expect(JSON.parse(await readFile(deepSwePath, "utf8")).rows).toHaveLength(1);
			expect(JSON.parse(await readFile(terminalPath, "utf8")).rows).toHaveLength(1);
			await expect(readFile(missingContextPath, "utf8")).rejects.toThrow();
		} finally {
			globalThis.fetch = originalFetch;
			await rm(directory, { recursive: true, force: true });
		}
	});
});

describe("percentile capability scoring", () => {
	test("calculates tie-aware percentile ranks", () => {
		expect([...percentileRanks([{ model: "a", value: 10 }, { model: "b", value: 20 }, { model: "c", value: 30 }, { model: "d", value: 40 }, { model: "e", value: 50 }])]).toEqual([
			["a", 0],
			["b", 0.25],
			["c", 0.5],
			["d", 0.75],
			["e", 1],
		]);
		expect(percentileRanks([{ model: "a", value: 20 }, { model: "b", value: 20 }, { model: "c", value: 10 }])).toEqual(
			new Map([
				["a", 0.75],
				["b", 0.75],
				["c", 0],
			]),
		);
	});

	test("lets new models change existing scores and uses each model's best observation", () => {
		expect(percentileRanks([{ model: "a", value: 10 }, { model: "b", value: 20 }]).get("b")).toBe(1);
		expect(percentileRanks([{ model: "a", value: 10 }, { model: "b", value: 20 }, { model: "b", value: 15 }, { model: "c", value: 30 }]).get("b")).toBe(0.5);
	});

	test("blends multiple sources and falls back missing source weight to manual policy", () => {
		const mapping = {
			manualWeight: 0.3,
			sources: [
				{ source: "deepswe-v1.1" as const, weight: 0.4 },
				{ source: "terminal-bench-2.1" as const, weight: 0.3 },
			],
		};
		expect(blendCapabilityScore(5, mapping, { "deepswe-v1.1": 1, "terminal-bench-2.1": 3 })).toBe(3);
		expect(blendCapabilityScore(5, mapping, { "deepswe-v1.1": 1 })).toBe(3);
	});

	test("includes unreviewed models in the reference population", () => {
		const deepSwe = normalizeDeepSwe(
			rawPayload([
				rawRow("gpt-5-6-sol", "max", { pass_at_1: 0.5 }),
				rawRow("unknown-a", "max", { pass_at_1: 0.6 }),
				rawRow("unknown-b", "max", { pass_at_1: 0.7 }),
				rawRow("unknown-c", "max", { pass_at_1: 0.8 }),
				rawRow("unknown-d", "max", { pass_at_1: 0.9 }),
			]),
		);
		expect(benchmarkCapabilityScores(deepSwe, terminalSnapshot([])).implementation?.get("gpt-5.6-sol")).toBe(2);
	});

	test("uses Terminal-Bench for investigation and leaves missing models unscored", () => {
		const scores = benchmarkCapabilityScores(
			snapshot([]),
			terminalSnapshot([
				terminalRow("gpt-5.6-sol", 60, "gpt-5.6-sol"),
				terminalRow("gpt-5.6-terra", 80, "gpt-5.6-terra"),
				terminalRow("unknown", 70),
			]),
		).investigation;
		expect(scores?.get("gpt-5.6-sol")).toBe(4);
		expect(scores?.get("gpt-5.6-terra")).toBe(5);
		expect(scores?.get("claude-haiku-4.5")).toBe(2);
	});
});

describe("generated Markdown", () => {
	test("renders one model table with intrinsic cost", () => {
		const table = renderRegions(snapshot([]))["model-selection"];
		expect(table).toContain("| model | exploration | research | investigation | implementation | review | architecture | design | writing | synthesis | cost | speed |");
		expect(table).toContain("| GPT-5.6 Sol | 5 | 5 | 5 | 5 | 4 | 5 | 4 | 4 | 5 | 5 | 3 |");
	});

});

describe("generated region replacement", () => {
	const regions = Object.fromEntries(regionNames.map((name) => [name, `new ${name}`])) as Record<RegionName, string>;

	test("preserves prose", () => {
		const original = context();
		const generated = replaceGeneratedRegions(original, regions);
		expect(generated).toStartWith("before\n");
		expect(generated).toContain("prose after reasoning-effort");
		expect(generated).toEndWith("after\n");
		expect(staleRegions(original, regions)).toEqual(regionNames);
	});

	test("rejects missing, duplicate, reversed, and unknown markers", () => {
		const valid = context();
		expect(() => replaceGeneratedRegions(valid.replace("<!-- BEGIN GENERATED: model-selection -->", ""), regions)).toThrow("Expected exactly one marker pair");
		expect(() => replaceGeneratedRegions(valid.replace("<!-- END GENERATED: model-selection -->", "<!-- BEGIN GENERATED: model-selection -->"), regions)).toThrow("Expected exactly one marker pair");
		const reversed = valid
			.replace("<!-- BEGIN GENERATED: model-selection -->", "TEMP MODEL MARKER")
			.replace("<!-- END GENERATED: model-selection -->", "<!-- BEGIN GENERATED: model-selection -->")
			.replace("TEMP MODEL MARKER", "<!-- END GENERATED: model-selection -->");
		expect(() => replaceGeneratedRegions(reversed, regions)).toThrow("reversed markers");
		expect(() => replaceGeneratedRegions(`${valid}<!-- BEGIN GENERATED: surprise -->\n<!-- END GENERATED: surprise -->\n`, regions)).toThrow("Unknown generated region surprise");
	});
});
