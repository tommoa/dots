import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import {
	classifyLiteLLMRoute,
	entryID,
	modelInfo,
	type LiteLLMModelEntry,
	type LiteLLMModelInfo,
	type LiteLLMRoute,
} from "./litellm/routing";

type ReasoningEffort = "none" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max" | "ultra";

interface AIProxyOptions {
	baseUrl: string;
	apiKeyEnv?: string;
	keyFile?: string;
	headers?: Record<string, string>;
	routeOverrides?: { responses?: string[]; chat?: string[] };
}

interface DiscoveredModel {
	id: string;
	displayName: string;
	route: LiteLLMRoute;
	contextLength?: number;
	inputModalities: string[];
	reasoningEfforts: ReasoningEffort[];
}

interface CLIProxyModel {
	name: string;
	alias: string;
	"display-name": string;
	"max-context-length"?: number;
	"input-modalities": string[];
	thinking: { levels: ReasoningEffort[] };
}

type CLIProxyConfig = Record<string, unknown>;

const reasoningEffortOrder: ReasoningEffort[] = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"];

function readJSON<T>(path: string): T {
	return JSON.parse(readFileSync(path, "utf8")) as T;
}

function normalizeUrl(value: string) {
	return value.trim().replace(/\/+$/, "");
}

function apiBaseUrl(baseUrl: string) {
	const normalized = normalizeUrl(baseUrl);
	return normalized.endsWith("/v1") ? normalized : `${normalized}/v1`;
}

function positiveInteger(...values: unknown[]) {
	return values.find((value): value is number => typeof value === "number" && Number.isInteger(value) && value > 0);
}

function inputModalities(info: LiteLLMModelInfo) {
	const modalities = ["text"];
	if (info.supports_vision) modalities.push("image");
	if (info.supports_pdf_input) modalities.push("pdf");
	if (info.supports_audio_input) modalities.push("audio");
	return modalities;
}

/**
 * LiteLLM's baseline for a reasoning-capable model is {low, medium, high};
 * additional tiers (none, minimal, xhigh, max, ultra) are opt-in via their
 * per-level `supports_*_reasoning_effort` flags, and any baseline tier can be
 * explicitly removed by setting its flag to false. CLIProxyAPI would otherwise
 * invent low/medium/high when `thinking` is omitted, so every model gets an
 * explicit list here.
 */
function reasoningEfforts(info: LiteLLMModelInfo): ReasoningEffort[] {
	if (info.supports_reasoning !== true) return [];
	const efforts = new Set<ReasoningEffort>(["low", "medium", "high"]);
	for (const [effort, supported] of [
		["none", info.supports_none_reasoning_effort],
		["minimal", info.supports_minimal_reasoning_effort],
		["low", info.supports_low_reasoning_effort],
		["medium", info.supports_medium_reasoning_effort],
		["high", info.supports_high_reasoning_effort],
		["xhigh", info.supports_xhigh_reasoning_effort],
		["max", info.supports_max_reasoning_effort],
		["ultra", info.supports_ultra_reasoning_effort],
	] as const) {
		if (supported === true) efforts.add(effort);
		if (supported === false) efforts.delete(effort);
	}
	return reasoningEffortOrder.filter((effort) => efforts.has(effort));
}

function isEmbedding(entry: LiteLLMModelEntry, id: string) {
	return id.toLowerCase().includes("embedding") || modelInfo(entry).mode === "embedding";
}

export function transformModels(entries: LiteLLMModelEntry[], options: Pick<AIProxyOptions, "routeOverrides"> = {}) {
	const models = new Map<string, DiscoveredModel>();
	for (const entry of entries) {
		const id = entryID(entry)?.trim();
		if (!id || isEmbedding(entry, id) || models.has(id)) continue;
		const info = modelInfo(entry);
		models.set(id, {
			id,
			displayName: entry.name?.trim() || id,
			route: classifyLiteLLMRoute(entry, { routeOverrides: options.routeOverrides }),
			contextLength: positiveInteger(
				info.max_input_tokens,
				entry.max_input_tokens,
				info.max_tokens,
				entry.context_window,
				entry.max_tokens,
			),
			inputModalities: inputModalities(info),
			reasoningEfforts: reasoningEfforts(info),
		});
	}
	return [...models.values()].sort((left, right) => left.id.localeCompare(right.id));
}

function modelConfig(model: DiscoveredModel): CLIProxyModel {
	return {
		name: model.id,
		alias: model.id,
		"display-name": `${model.displayName} (ai-proxy)`,
		...(model.contextLength ? { "max-context-length": model.contextLength } : {}),
		"input-modalities": model.inputModalities,
		thinking: { levels: model.reasoningEfforts },
	};
}

function appendConfigEntry(config: CLIProxyConfig, key: string, entry: Record<string, unknown>) {
	const existing = config[key];
	config[key] = [...(Array.isArray(existing) ? existing : []), entry];
}

export function buildCLIProxyConfig(
	baseConfig: CLIProxyConfig,
	models: DiscoveredModel[],
	apiKey: string,
	baseUrl: string,
	headers: Record<string, string> = {},
) {
	const config = structuredClone(baseConfig);
	const responsesModels = models.filter((model) => model.route === "responses").map(modelConfig);
	const chatModels = models.filter((model) => model.route === "chat").map(modelConfig);
	if (responsesModels.length === 0 && chatModels.length === 0) return config;

	// Raw ai-proxy IDs can collide with subscription models, so the namespace is mandatory.
	config["force-model-prefix"] = true;
	const providerHeaders = Object.keys(headers).length > 0 ? { headers } : {};
	if (responsesModels.length > 0) {
		appendConfigEntry(config, "codex-api-key", {
			"api-key": apiKey,
			prefix: "ai-proxy",
			"base-url": baseUrl,
			models: responsesModels,
			...providerHeaders,
		});
	}
	if (chatModels.length > 0) {
		appendConfigEntry(config, "openai-compatibility", {
			name: "ai-proxy",
			prefix: "ai-proxy",
			"base-url": baseUrl,
			"api-key-entries": [{ "api-key": apiKey }],
			models: chatModels,
			...providerHeaders,
		});
	}
	return config;
}

function readAPIKey(options: AIProxyOptions) {
	const environmentKey = options.apiKeyEnv?.trim() ? process.env[options.apiKeyEnv.trim()]?.trim() : undefined;
	if (environmentKey) return environmentKey;
	if (!options.keyFile) return;
	try {
		return readFileSync(options.keyFile, "utf8").trim() || undefined;
	} catch (error) {
		// ENOENT is expected before first provisioning; surface anything else
		// (permissions, IO faults) so the refresh log points at the real cause
		// instead of the generic "API key unavailable" downstream error.
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
			const reason = error instanceof Error ? error.message : String(error);
			console.error(`[cli-proxy-api] Failed to read keyFile ${options.keyFile}: ${reason}`);
		}
		return;
	}
}

export function sanitizedHeaders(headers: Record<string, string> = {}) {
	// Refuse Authorization-shaped entries: the caller wires the API key via
	// env/keyFile, so anything Authorization-flavored in headers would either
	// duplicate that channel or, worse, bake a static token into the store
	// path this options file is generated from.
	for (const name of Object.keys(headers)) {
		if (name.toLowerCase() === "authorization") {
			throw new Error(
				`ai-proxy headers must not contain an Authorization entry; use apiKeyEnv/keyFile (offending key: ${name})`,
			);
		}
	}
	return headers;
}

async function discoverModels(options: AIProxyOptions, apiKey: string) {
	const headers: Record<string, string> = {
		...sanitizedHeaders(options.headers),
		Authorization: `Bearer ${apiKey}`,
	};
	const url = `${normalizeUrl(options.baseUrl)}/model/info`;
	const response = await fetch(url, { headers, signal: AbortSignal.timeout(30_000) });
	if (!response.ok) throw new Error(`GET ${url} failed with ${response.status} ${response.statusText}`);
	const payload = (await response.json()) as { data?: LiteLLMModelEntry[] };
	if (!Array.isArray(payload.data)) throw new Error(`GET ${url} returned no data array`);
	const models = transformModels(payload.data, options);
	if (models.length === 0) throw new Error(`GET ${url} returned no usable models`);
	return models;
}

function publishJSON(path: string, value: unknown) {
	mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
	const contents = `${JSON.stringify(value, null, 2)}\n`;
	try {
		if (readFileSync(path, "utf8") === contents) return;
	} catch {
		// The activation creates the file before normal refreshes begin.
	}
	// CLIProxyAPI watches this inode rather than its parent directory. Replacing
	// it with rename can detach the watcher after the first periodic refresh.
	writeFileSync(path, contents, { mode: 0o600 });
	chmodSync(path, 0o600);
}

async function main() {
	const [baseConfigPath, optionsPath, outputPath] = process.argv.slice(2);
	if (!baseConfigPath || !optionsPath || !outputPath) throw new Error("usage: cli-proxy-api-config BASE OPTIONS OUTPUT");
	const baseConfig = readJSON<CLIProxyConfig>(baseConfigPath);
	const options = readJSON<AIProxyOptions>(optionsPath);
	const apiKey = readAPIKey(options);
	if (!apiKey) throw new Error("ai-proxy API key is unavailable");
	const models = await discoverModels(options, apiKey);
	publishJSON(
		outputPath,
		buildCLIProxyConfig(baseConfig, models, apiKey, apiBaseUrl(options.baseUrl), sanitizedHeaders(options.headers)),
	);
	console.error(`[cli-proxy-api] Published ${models.length} discovered ai-proxy models.`);
}

if (import.meta.main) {
	try {
		await main();
	} catch (error) {
		const reason = error instanceof Error ? error.message : String(error);
		console.error(`[cli-proxy-api] Model refresh failed without changing the runtime config: ${reason}`);
		process.exitCode = 1;
	}
}
