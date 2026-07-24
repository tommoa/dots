import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
	benchmarkMappings,
	modelByBenchmarkAlias,
	models,
	taskTypes,
	type BenchmarkMapping,
	type BenchmarkSource,
	type TaskType,
} from "./policy";

/**
 * Builds the generated regions in context.md from reviewed policy and checked-in
 * benchmark snapshots. The source context intentionally keeps those regions
 * blank; Home Manager runs `generate` on a copy in the Nix store.
 *
 * Manual maintenance:
 * - Edit fallback capability, cost, speed, eligibility, aliases, and effort
 *   recommendations in policy.ts.
 * - Edit `passAt1` in the DeepSWE snapshot or `accuracy` in the Terminal-Bench
 *   snapshot to override benchmark input temporarily. The best row for each
 *   source model is used. Running `refresh` overwrites snapshot edits.
 * - Run `refresh` only through the model-benchmarks pseudo-input (or directly)
 *   when network-backed benchmark data should change. Normal Nix builds are
 *   offline and only read the checked-in snapshots.
 */
export const DEEPSWE_SOURCE = "https://deepswe.datacurve.ai/artifacts/v1.1/leaderboard-live.json";
export const TERMINAL_BENCH_SOURCE = "https://api.github.com/repos/harbor-framework/terminal-bench-2-1/contents/leaderboard/submissions?ref=main";

const defaultContextPath = resolve(import.meta.dir, "../context.md");
const defaultSnapshotPath = resolve(import.meta.dir, "snapshots/deepswe-v1.1.json");
const defaultTerminalSnapshotPath = resolve(import.meta.dir, "snapshots/terminal-bench-2.1.json");
const effortOrder = ["default", "low", "medium", "high", "xhigh", "max"];

export interface BenchmarkRow {
	sourceModel: string;
	canonicalModel?: string;
	effort: string;
	passAt1: number;
	meanCostUsd: number;
	meanInputTokens: number;
	meanOutputTokens: number;
	meanAgentSteps: number;
	taskCount: number;
	runCount: number;
}

export interface BenchmarkSnapshot {
	schemaVersion: 1;
	benchmark: "DeepSWE v1.1";
	source: string;
	taskCount: number;
	rows: BenchmarkRow[];
}

export interface TerminalBenchRow {
	sourceFile: string;
	sourceModel: string;
	canonicalModel?: string;
	effort: string;
	agent: string;
	date: string;
	accuracy: number;
	trialCount: number;
	rewardHackPercent: number;
}

export interface TerminalBenchSnapshot {
	schemaVersion: 1;
	benchmark: "Terminal-Bench 2.1";
	source: string;
	license: "Apache-2.0";
	rows: TerminalBenchRow[];
}

export interface TerminalSubmission {
	sourceFile: string;
	payload: unknown;
}

export const regionNames = ["model-selection", "reasoning-effort"] as const;
export type RegionName = (typeof regionNames)[number];

type GeneratedRegions = Record<RegionName, string>;

export function normalizeDeepSwe(payload: unknown): BenchmarkSnapshot {
	const root = object(payload, "DeepSWE payload");
	const taskCount = integer(root.n_tasks_in_set, "n_tasks_in_set");
	if (taskCount <= 0) throw new Error("n_tasks_in_set must be positive");
	if (typeof root.scope !== "string" || !root.scope.includes("DeepSWE rollout")) throw new Error("Unexpected DeepSWE scope");
	if (typeof root.unit !== "string" || !root.unit.includes("pass@1")) throw new Error("Unexpected DeepSWE unit description");
	if (!Array.isArray(root.rows)) throw new Error("DeepSWE payload rows must be an array");

	const seen = new Set<string>();
	const rows = root.rows.map((value, index) => {
		const row = object(value, `rows[${index}]`);
		const sourceModel = string(row.model, `rows[${index}].model`);
		const effort = row.reasoning_effort === null ? "default" : string(row.reasoning_effort, `rows[${index}].reasoning_effort`);
		if (!effortOrder.includes(effort)) throw new Error(`Unsupported reasoning effort ${effort} for ${sourceModel}`);
		if (row.harness !== "mini-swe-agent" || row.source !== "deep-swe") throw new Error(`Unexpected benchmark source for ${sourceModel}/${effort}`);

		const key = `${sourceModel}/${effort}`;
		if (seen.has(key)) throw new Error(`Duplicate DeepSWE configuration ${key}`);
		seen.add(key);

		const passAt1 = finiteNumber(row.pass_at_1, `${key}.pass_at_1`);
		if (passAt1 < 0 || passAt1 > 1) throw new Error(`${key}.pass_at_1 must be between 0 and 1`);
		const rowTaskCount = integer(row.n_tasks_attempted, `${key}.n_tasks_attempted`);
		if (rowTaskCount <= 0 || rowTaskCount > taskCount) throw new Error(`${key}.n_tasks_attempted is outside the benchmark task set`);

		const policy = modelByBenchmarkAlias.get(sourceModel);
		return {
			sourceModel,
			...(policy ? { canonicalModel: policy.id } : {}),
			effort,
			passAt1,
			meanCostUsd: nonNegativeNumber(row.mean_cost_usd, `${key}.mean_cost_usd`),
			meanInputTokens: nonNegativeNumber(row.mean_input_tokens, `${key}.mean_input_tokens`),
			meanOutputTokens: nonNegativeNumber(row.mean_output_tokens, `${key}.mean_output_tokens`),
			meanAgentSteps: nonNegativeNumber(row.mean_agent_steps, `${key}.mean_agent_steps`),
			taskCount: rowTaskCount,
			runCount: positiveInteger(row.n_runs, `${key}.n_runs`),
		};
	});

	rows.sort((left, right) => left.sourceModel.localeCompare(right.sourceModel) || compareEffort(left.effort, right.effort));
	return {
		schemaVersion: 1,
		benchmark: "DeepSWE v1.1",
		source: DEEPSWE_SOURCE,
		taskCount,
		rows,
	};
}

export function parseSnapshot(value: unknown): BenchmarkSnapshot {
	const root = object(value, "benchmark snapshot");
	if (root.schemaVersion !== 1) throw new Error("Unsupported benchmark snapshot schema version");
	if (root.benchmark !== "DeepSWE v1.1") throw new Error("Unexpected benchmark snapshot name");
	if (root.source !== DEEPSWE_SOURCE) throw new Error("Unexpected benchmark snapshot source");
	const taskCount = positiveInteger(root.taskCount, "snapshot.taskCount");
	if (!Array.isArray(root.rows)) throw new Error("Benchmark snapshot rows must be an array");

	const seen = new Set<string>();
	const rows = root.rows.map((value, index) => {
		const row = object(value, `snapshot.rows[${index}]`);
		const sourceModel = string(row.sourceModel, `snapshot.rows[${index}].sourceModel`);
		const effort = string(row.effort, `snapshot.rows[${index}].effort`);
		if (!effortOrder.includes(effort)) throw new Error(`Unsupported snapshot reasoning effort ${effort}`);
		const canonicalModel = row.canonicalModel === undefined ? undefined : string(row.canonicalModel, `snapshot.rows[${index}].canonicalModel`);
		const policy = modelByBenchmarkAlias.get(sourceModel);
		if (canonicalModel !== policy?.id) throw new Error(`Stale benchmark alias mapping for ${sourceModel}`);
		const key = `${sourceModel}/${effort}`;
		if (seen.has(key)) throw new Error(`Duplicate benchmark snapshot row ${key}`);
		seen.add(key);

		const passAt1 = finiteNumber(row.passAt1, `${key}.passAt1`);
		if (passAt1 < 0 || passAt1 > 1) throw new Error(`${key}.passAt1 must be between 0 and 1`);
		return {
			sourceModel,
			...(canonicalModel ? { canonicalModel } : {}),
			effort,
			passAt1,
			meanCostUsd: nonNegativeNumber(row.meanCostUsd, `${key}.meanCostUsd`),
			meanInputTokens: nonNegativeNumber(row.meanInputTokens, `${key}.meanInputTokens`),
			meanOutputTokens: nonNegativeNumber(row.meanOutputTokens, `${key}.meanOutputTokens`),
			meanAgentSteps: nonNegativeNumber(row.meanAgentSteps, `${key}.meanAgentSteps`),
			taskCount: positiveInteger(row.taskCount, `${key}.taskCount`),
			runCount: positiveInteger(row.runCount, `${key}.runCount`),
		};
	});

	const sorted = [...rows].sort((left, right) => left.sourceModel.localeCompare(right.sourceModel) || compareEffort(left.effort, right.effort));
	if (JSON.stringify(rows) !== JSON.stringify(sorted)) throw new Error("Benchmark snapshot rows are not canonically sorted");
	return { schemaVersion: 1, benchmark: "DeepSWE v1.1", source: DEEPSWE_SOURCE, taskCount, rows };
}

export function normalizeTerminalBench(submissions: TerminalSubmission[]): TerminalBenchSnapshot {
	const seen = new Set<string>();
	const rows = submissions.map(({ sourceFile, payload }, index) => {
		if (!sourceFile.endsWith(".json") || seen.has(sourceFile)) throw new Error(`Invalid or duplicate Terminal-Bench source file ${sourceFile}`);
		seen.add(sourceFile);
		const root = object(payload, `Terminal-Bench submission ${sourceFile || index}`);
		const sourceFilter = object(root.source_filter, `${sourceFile}.source_filter`);
		const metadata = object(root.metadata, `${sourceFile}.metadata`);
		const metrics = object(root.metrics, `${sourceFile}.metrics`);
		const rawModel = string(sourceFilter.model_name, `${sourceFile}.source_filter.model_name`);
		const sourceModel = stripProvider(rawModel);
		const effortValue = metadata.reasoning_effort ?? sourceFilter.reasoning_effort;
		const effort = effortValue === null || effortValue === "none" ? "default" : string(effortValue, `${sourceFile}.reasoning_effort`);
		if (!effortOrder.includes(effort)) throw new Error(`Unsupported Terminal-Bench reasoning effort ${effort} for ${sourceModel}`);
		const accuracy = finiteNumber(metrics.accuracy, `${sourceFile}.metrics.accuracy`);
		if (accuracy < 0 || accuracy > 100) throw new Error(`${sourceFile}.metrics.accuracy must be between 0 and 100`);
		const policy = benchmarkPolicy(sourceModel);
		return {
			sourceFile,
			sourceModel,
			...(policy ? { canonicalModel: policy.id } : {}),
			effort,
			agent: string(sourceFilter.agent, `${sourceFile}.source_filter.agent`),
			date: isoDate(metadata.date, `${sourceFile}.metadata.date`),
			accuracy,
			trialCount: positiveInteger(metrics.n_trials, `${sourceFile}.metrics.n_trials`),
			rewardHackPercent: nonNegativeNumber(metrics.reward_hacks, `${sourceFile}.metrics.reward_hacks`),
		};
	});
	rows.sort((left, right) => left.sourceFile.localeCompare(right.sourceFile));
	return {
		schemaVersion: 1,
		benchmark: "Terminal-Bench 2.1",
		source: TERMINAL_BENCH_SOURCE,
		license: "Apache-2.0",
		rows,
	};
}

export function parseTerminalSnapshot(value: unknown): TerminalBenchSnapshot {
	const root = object(value, "Terminal-Bench snapshot");
	if (root.schemaVersion !== 1 || root.benchmark !== "Terminal-Bench 2.1") throw new Error("Unsupported Terminal-Bench snapshot");
	if (root.source !== TERMINAL_BENCH_SOURCE || root.license !== "Apache-2.0") throw new Error("Unexpected Terminal-Bench snapshot provenance");
	if (!Array.isArray(root.rows)) throw new Error("Terminal-Bench snapshot rows must be an array");
	const rows = root.rows.map((value, index) => {
		const row = object(value, `Terminal-Bench snapshot row ${index}`);
		const sourceFile = string(row.sourceFile, `terminal.rows[${index}].sourceFile`);
		const sourceModel = string(row.sourceModel, `${sourceFile}.sourceModel`);
		const canonicalModel = row.canonicalModel === undefined ? undefined : string(row.canonicalModel, `${sourceFile}.canonicalModel`);
		if (canonicalModel !== benchmarkPolicy(sourceModel)?.id) throw new Error(`Stale Terminal-Bench alias mapping for ${sourceModel}`);
		const effort = string(row.effort, `${sourceFile}.effort`);
		if (!effortOrder.includes(effort)) throw new Error(`Unsupported Terminal-Bench snapshot effort ${effort}`);
		const accuracy = finiteNumber(row.accuracy, `${sourceFile}.accuracy`);
		if (accuracy < 0 || accuracy > 100) throw new Error(`${sourceFile}.accuracy must be between 0 and 100`);
		return {
			sourceFile,
			sourceModel,
			...(canonicalModel ? { canonicalModel } : {}),
			effort,
			agent: string(row.agent, `${sourceFile}.agent`),
			date: isoDate(row.date, `${sourceFile}.date`),
			accuracy,
			trialCount: positiveInteger(row.trialCount, `${sourceFile}.trialCount`),
			rewardHackPercent: nonNegativeNumber(row.rewardHackPercent, `${sourceFile}.rewardHackPercent`),
		};
	});
	const sourceFiles = new Set(rows.map((row) => row.sourceFile));
	if (sourceFiles.size !== rows.length) throw new Error("Duplicate Terminal-Bench snapshot source file");
	const sorted = [...rows].sort((left, right) => left.sourceFile.localeCompare(right.sourceFile));
	if (JSON.stringify(rows) !== JSON.stringify(sorted)) throw new Error("Terminal-Bench snapshot rows are not canonically sorted");
	return { schemaVersion: 1, benchmark: "Terminal-Bench 2.1", source: TERMINAL_BENCH_SOURCE, license: "Apache-2.0", rows };
}

export function renderRegions(snapshot: BenchmarkSnapshot, terminalSnapshot: TerminalBenchSnapshot = emptyTerminalSnapshot()): GeneratedRegions {
	return {
		"model-selection": renderModelSelection(snapshot, terminalSnapshot),
		"reasoning-effort": renderReasoningEffort(),
	};
}

export function replaceGeneratedRegions(source: string, regions: GeneratedRegions): string {
	validateMarkers(source);
	let result = source;
	for (const name of regionNames) {
		const begin = beginMarker(name);
		const end = endMarker(name);
		const beginIndex = result.indexOf(begin);
		const endIndex = result.indexOf(end, beginIndex + begin.length);
		result = `${result.slice(0, beginIndex)}${regions[name]}${result.slice(endIndex + end.length)}`;
	}
	return result;
}

export function staleRegions(source: string, regions: GeneratedRegions): RegionName[] {
	validateMarkers(source);
	return regionNames.filter((name) => {
		const begin = beginMarker(name);
		const end = endMarker(name);
		const beginIndex = source.indexOf(begin);
		const endIndex = source.indexOf(end, beginIndex + begin.length);
		return source.slice(beginIndex + begin.length, endIndex) !== `\n${regions[name]}\n`;
	});
}

export function percentileRanks(observations: { model: string; value: number }[]) {
	// Midrank percentiles keep ties equal and let new reference models move
	// existing scores without storing score history.
	const bestByModel = new Map<string, number>();
	for (const observation of observations) {
		if (!Number.isFinite(observation.value)) throw new Error(`Invalid percentile value for ${observation.model}`);
		const current = bestByModel.get(observation.model);
		if (current === undefined || observation.value > current) bestByModel.set(observation.model, observation.value);
	}
	const values = [...bestByModel.values()];
	const ranks = new Map<string, number>();
	for (const [model, value] of bestByModel) {
		const lower = values.filter((candidate) => candidate < value).length;
		const equal = values.filter((candidate) => candidate === value).length;
		const percentile = values.length === 1 ? 0.5 : (lower + (equal - 1) / 2) / (values.length - 1);
		ranks.set(model, percentile);
	}
	return ranks;
}

export function benchmarkCapabilityScores(snapshot: BenchmarkSnapshot, terminalSnapshot: TerminalBenchSnapshot) {
	const sources = new Map<BenchmarkSource, Map<string, number>>([
		[
			"deepswe-v1.1",
			reviewedBenchmarkScores(
			snapshot.rows.map((row) => ({ model: row.sourceModel, canonicalModel: row.canonicalModel, value: row.passAt1 })),
		),
		],
		[
			"terminal-bench-2.1",
			reviewedBenchmarkScores(
			terminalSnapshot.rows.map((row) => ({ model: row.sourceModel, canonicalModel: row.canonicalModel, value: row.accuracy })),
		),
		],
	]);
	return Object.fromEntries(
		Object.entries(benchmarkMappings).map(([task, mapping]) => [task, blendedCapabilityScores(task as TaskType, mapping, sources)]),
	) as Partial<Record<TaskType, Map<string, number>>>;
}

function renderModelSelection(snapshot: BenchmarkSnapshot, terminalSnapshot: TerminalBenchSnapshot) {
	const headers = ["model", ...taskTypes, "cost", "speed"];
	const benchmarkScores = benchmarkCapabilityScores(snapshot, terminalSnapshot);
	const rows = models.map((model) => [
		model.name,
		...taskTypes.map((task) => benchmarkScores[task]?.get(model.id) ?? model.capabilities[task]),
		model.cost,
		model.speed,
	]);
	return markdownTable(headers, rows, new Set(headers.slice(1)));
}

function reviewedBenchmarkScores(observations: { model: string; canonicalModel?: string; value: number }[]) {
	const percentiles = percentileRanks(observations);
	const result = new Map<string, number>();
	for (const observation of observations) {
		if (!observation.canonicalModel) continue;
		const percentile = percentiles.get(observation.model);
		if (percentile !== undefined) result.set(observation.canonicalModel, 1 + 4 * percentile);
	}
	return result;
}

function blendedCapabilityScores(task: TaskType, mapping: BenchmarkMapping, sourceScores: Map<BenchmarkSource, Map<string, number>>) {
	validateBenchmarkMapping(task, mapping);
	return new Map(
		models.map((model) => {
			const available = Object.fromEntries(mapping.sources.map(({ source }) => [source, sourceScores.get(source)?.get(model.id)])) as Partial<Record<BenchmarkSource, number>>;
			return [model.id, blendCapabilityScore(model.capabilities[task], mapping, available)];
		}),
	);
}

export function blendCapabilityScore(manualScore: number, mapping: BenchmarkMapping, sourceScores: Partial<Record<BenchmarkSource, number>>) {
	// Each source keeps its own policy weight. Missing model coverage gives that
	// weight back to the manual score rather than amplifying another benchmark.
	let blended = manualScore * mapping.manualWeight;
	for (const source of mapping.sources) blended += (sourceScores[source.source] ?? manualScore) * source.weight;
	return Math.max(1, Math.min(5, Math.round(blended)));
}

function validateBenchmarkMapping(task: TaskType, mapping: BenchmarkMapping) {
	const weights = [mapping.manualWeight, ...mapping.sources.map((source) => source.weight)];
	if (weights.some((weight) => !Number.isFinite(weight) || weight < 0)) throw new Error(`Invalid benchmark weight for ${task}`);
	const total = weights.reduce((sum, weight) => sum + weight, 0);
	if (Math.abs(total - 1) > 1e-9) throw new Error(`Benchmark weights for ${task} must sum to one`);
	const sources = new Set(mapping.sources.map((source) => source.source));
	if (sources.size !== mapping.sources.length) throw new Error(`Duplicate benchmark source for ${task}`);
}

function renderReasoningEffort() {
	return markdownTable(
		["model", "routine work", "difficult work", "extreme work"],
		models.map((model) => [model.name, model.effort.routine, model.effort.difficult, model.effort.extreme]),
	);
}

function markdownTable(headers: readonly string[], rows: (string | number)[][], rightAligned = new Set<string>()) {
	const header = `| ${headers.join(" | ")} |`;
	const separator = `|${headers.map((item) => (rightAligned.has(item) ? "---:" : "---")).join("|")}|`;
	return [header, separator, ...rows.map((row) => `| ${row.join(" | ")} |`)].join("\n");
}

function validateMarkers(source: string) {
	const known = new Set<string>(regionNames);
	for (const match of source.matchAll(/<!-- (?:BEGIN|END) GENERATED: ([a-z0-9-]+) -->/g)) {
		if (!known.has(match[1])) throw new Error(`Unknown generated region ${match[1]}`);
	}
	for (const name of regionNames) {
		const begin = beginMarker(name);
		const end = endMarker(name);
		if (count(source, begin) !== 1 || count(source, end) !== 1) throw new Error(`Expected exactly one marker pair for ${name}`);
		if (source.indexOf(begin) > source.indexOf(end)) throw new Error(`Generated region ${name} has reversed markers`);
	}
}

function beginMarker(name: RegionName) {
	return `<!-- BEGIN GENERATED: ${name} -->`;
}

function endMarker(name: RegionName) {
	return `<!-- END GENERATED: ${name} -->`;
}

function count(source: string, needle: string) {
	return source.split(needle).length - 1;
}

function benchmarkPolicy(sourceModel: string) {
	return modelByBenchmarkAlias.get(stripProvider(sourceModel));
}

function stripProvider(model: string) {
	const separator = model.indexOf("/");
	return separator === -1 ? model : model.slice(separator + 1);
}

function isoDate(value: unknown, label: string) {
	const result = string(value, label);
	if (!/^\d{4}-\d{2}-\d{2}$/.test(result)) throw new Error(`${label} must be an ISO date`);
	return result;
}

function emptyTerminalSnapshot(): TerminalBenchSnapshot {
	return {
		schemaVersion: 1,
		benchmark: "Terminal-Bench 2.1",
		source: TERMINAL_BENCH_SOURCE,
		license: "Apache-2.0",
		rows: [],
	};
}

function compareEffort(left: string, right: string) {
	return effortOrder.indexOf(left) - effortOrder.indexOf(right);
}

function object(value: unknown, label: string): Record<string, unknown> {
	if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${label} must be an object`);
	return value as Record<string, unknown>;
}

function string(value: unknown, label: string) {
	if (typeof value !== "string" || value.length === 0) throw new Error(`${label} must be a non-empty string`);
	return value;
}

function finiteNumber(value: unknown, label: string) {
	if (typeof value !== "number" || !Number.isFinite(value)) throw new Error(`${label} must be a finite number`);
	return value;
}

function nonNegativeNumber(value: unknown, label: string) {
	const result = finiteNumber(value, label);
	if (result < 0) throw new Error(`${label} must not be negative`);
	return result;
}

function integer(value: unknown, label: string) {
	const result = finiteNumber(value, label);
	if (!Number.isInteger(result)) throw new Error(`${label} must be an integer`);
	return result;
}

function positiveInteger(value: unknown, label: string) {
	const result = integer(value, label);
	if (result <= 0) throw new Error(`${label} must be positive`);
	return result;
}

export interface CommandOptions {
	command: "generate" | "check" | "refresh";
	contextPath: string;
	snapshotPath: string;
	terminalSnapshotPath: string;
	source: string;
}

function parseArguments(args: string[]): CommandOptions {
	const command = args.shift();
	if (command !== "generate" && command !== "check" && command !== "refresh")
		throw new Error("Usage: generator.ts <generate|check|refresh> [--context PATH] [--snapshot PATH] [--terminal-snapshot PATH] [--source URL]");
	let contextPath = defaultContextPath;
	let snapshotPath = defaultSnapshotPath;
	let terminalSnapshotPath = defaultTerminalSnapshotPath;
	let source = DEEPSWE_SOURCE;
	while (args.length > 0) {
		const flag = args.shift();
		const value = args.shift();
		if (!value) throw new Error(`Missing value for ${flag}`);
		if (flag === "--context") contextPath = resolve(value);
		else if (flag === "--snapshot") snapshotPath = resolve(value);
		else if (flag === "--terminal-snapshot") terminalSnapshotPath = resolve(value);
		else if (flag === "--source") source = value;
		else throw new Error(`Unknown option ${flag}`);
	}
	if (command !== "refresh" && source !== DEEPSWE_SOURCE) throw new Error("--source is only valid with refresh");
	return { command, contextPath, snapshotPath, terminalSnapshotPath, source };
}

async function loadSnapshot(path: string) {
	return parseSnapshot(JSON.parse(await readFile(path, "utf8")));
}

async function loadTerminalSnapshot(path: string) {
	return parseTerminalSnapshot(JSON.parse(await readFile(path, "utf8")));
}

async function fetchJson(url: string) {
	const response = await fetch(url, { signal: AbortSignal.timeout(30_000) });
	if (!response.ok) throw new Error(`GET ${url} failed with ${response.status} ${response.statusText}`);
	return response.json();
}

async function refreshTerminalBench() {
	const listing = await fetchJson(TERMINAL_BENCH_SOURCE);
	if (!Array.isArray(listing)) throw new Error("Terminal-Bench submission listing must be an array");
	const files = listing
		.map((value, index) => object(value, `Terminal-Bench listing item ${index}`))
		.filter((item) => item.type === "file" && typeof item.name === "string" && item.name.endsWith(".json"))
		.map((item) => ({ sourceFile: string(item.name, "Terminal-Bench filename"), url: string(item.download_url, `${item.name}.download_url`) }));
	if (files.length === 0) throw new Error("Terminal-Bench listing contains no JSON submissions");
	const submissions = await Promise.all(files.map(async (file) => ({ sourceFile: file.sourceFile, payload: await fetchJson(file.url) })));
	return normalizeTerminalBench(submissions);
}

export async function execute(options: CommandOptions) {
	if (options.command === "refresh") {
		const [snapshot, terminalSnapshot] = await Promise.all([fetchJson(options.source).then(normalizeDeepSwe), refreshTerminalBench()]);
		await writeFile(options.snapshotPath, `${JSON.stringify(snapshot, null, 2)}\n`);
		await writeFile(options.terminalSnapshotPath, `${JSON.stringify(terminalSnapshot, null, 2)}\n`);
		return;
	}

	const context = await readFile(options.contextPath, "utf8");
	const [snapshot, terminalSnapshot] = await Promise.all([loadSnapshot(options.snapshotPath), loadTerminalSnapshot(options.terminalSnapshotPath)]);
	const regions = renderRegions(snapshot, terminalSnapshot);
	if (options.command === "generate") {
		await writeFile(options.contextPath, replaceGeneratedRegions(context, regions));
		return;
	}
	const stale = staleRegions(context, regions);
	if (stale.length > 0) throw new Error(`Stale generated context regions: ${stale.join(", ")}`);
}

if (import.meta.main) {
	execute(parseArguments(process.argv.slice(2))).catch((error) => {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	});
}
