import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
	canonicalModelID,
	classifyLiteLLMRoute,
	entryID,
	modelInfo,
	splitDateSuffix,
	stripProviderPrefix,
	type LiteLLMModelEntry,
	type LiteLLMModelInfo,
	type LiteLLMRoute as RouteKind,
} from "./routing";

type Modality = "text" | "audio" | "image" | "video" | "pdf";

export interface LiteLLMOptions {
	baseUrl?: string;
	modelsUrl?: string;
	apiKeyEnv?: string;
	keyFile?: string;
	headers?: Record<string, string>;
	providerName?: string;
	routeOverrides?: {
		responses?: string[];
		chat?: string[];
	};
	defaults?: {
		context?: number;
		output?: number;
		input?: Modality[];
	};
}

export type { LiteLLMModelEntry } from "./routing";

interface LiteLLMModelsPayload {
	data?: LiteLLMModelEntry[];
}

export interface CatalogModelSnapshot {
	id: string;
	name?: string;
	family?: string;
	releaseDate?: string;
	status?: string;
	providerPackage?: string;
	capabilities?: {
		temperature?: boolean;
		reasoning?: boolean;
		attachment?: boolean;
		tools?: boolean;
		input?: Modality[];
		output?: Modality[];
		interleaved?: boolean | { field: "reasoning" | "reasoning_content" | "reasoning_details" };
	};
	cost?: {
		input?: number;
		output?: number;
		cache_read?: number;
		cache_write?: number;
		context_over_200k?: {
			input?: number;
			output?: number;
			cache_read?: number;
			cache_write?: number;
		};
	};
	limit?: {
		context?: number;
		input?: number;
		output?: number;
	};
	variants?: Record<string, Record<string, unknown>>;
}

export interface CatalogProviderSnapshot {
	id: string;
	models: CatalogModelSnapshot[];
}

export interface CatalogSnapshot {
	providers: CatalogProviderSnapshot[];
}

interface NormalizedModel {
	id: string;
	name: string;
	family?: string;
	releaseDate?: string;
	status?: string;
	route: RouteKind;
	capabilities: {
		temperature?: boolean;
		reasoning?: boolean;
		attachment?: boolean;
		tools?: boolean;
		input: Modality[];
		output: Modality[];
		interleaved?: boolean | { field: "reasoning" | "reasoning_content" | "reasoning_details" };
	};
	cost?: {
		input?: number;
		output?: number;
		cache_read?: number;
		cache_write?: number;
		context_over_200k?: {
			input?: number;
			output?: number;
			cache_read?: number;
			cache_write?: number;
		};
	};
	limit: {
		context: number;
		input?: number;
		output: number;
	};
	variants: Record<string, Record<string, unknown>>;
}

export interface DiscoveredLiteLLM {
	providerID: "litellm";
	providerName: string;
	baseUrl: string;
	apiKeyEnv: string;
	models: NormalizedModel[];
}

export type V2Model = Record<string, unknown>;

const COST_MULTIPLIER = 1_000_000;
const defaultBaseUrl = "https://ai-proxy.infra.corp.arista.io";
const defaultApiKeyEnv = "LITELLM_API_KEY";
const modelDiscoveryTimeoutMs = 30_000;
const canonicalProviderOrder = ["openai", "anthropic", "google", "opencode"];
const monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const brandMap: Record<string, string> = { claude: "Claude", gemini: "Gemini", gpt: "GPT" };
const tierWords: Record<string, string> = {
	opus: "Opus",
	sonnet: "Sonnet",
	haiku: "Haiku",
	pro: "Pro",
	flash: "Flash",
	ultra: "Ultra",
	nano: "Nano",
	codex: "Codex",
	mini: "Mini",
	preview: "Preview",
};

let cacheKey: string | undefined;
let cache: Promise<DiscoveredLiteLLM> | undefined;

export function warn(message: string) {
	console.warn(`[opencode-litellm] ${message}`);
}

export function normalizeOptions(options?: LiteLLMOptions) {
	return {
		baseUrl: normalizeUrl(options?.baseUrl ?? defaultBaseUrl),
		modelsUrl: options?.modelsUrl ? normalizeUrl(options.modelsUrl) : undefined,
		apiKeyEnv: options?.apiKeyEnv?.trim() || defaultApiKeyEnv,
		keyFile: expandHome(options?.keyFile ?? "~/.config/ai-keys/litellm"),
		headers: options?.headers ?? {},
		providerName: options?.providerName ?? "LiteLLM",
		routeOverrides: {
			responses: new Set(options?.routeOverrides?.responses ?? []),
			chat: new Set(options?.routeOverrides?.chat ?? []),
		},
		defaults: {
			context: options?.defaults?.context ?? 128_000,
			output: options?.defaults?.output ?? 16_384,
			input: options?.defaults?.input ?? ["text"],
		},
	};
}

export async function discoverLiteLLM(options?: LiteLLMOptions, catalog?: CatalogSnapshot): Promise<DiscoveredLiteLLM> {
	const normalized = normalizeOptions(options);
	const nextKey = JSON.stringify({
		...normalized,
		routeOverrides: {
			responses: [...normalized.routeOverrides.responses].sort(),
			chat: [...normalized.routeOverrides.chat].sort(),
		},
		catalogKey: catalogKey(catalog),
	});
	if (cache && cacheKey === nextKey) return cache;
	cacheKey = nextKey;
	cache = discover(normalized, catalog).catch((error) => {
		cache = undefined;
		cacheKey = undefined;
		throw error;
	});
	return cache;
}

export function buildDiscoveryFromEntries(entries: LiteLLMModelEntry[], modelsUrl: string, options?: LiteLLMOptions, catalog?: CatalogSnapshot): DiscoveredLiteLLM {
	const normalized = normalizeOptions(options);
	const models = entries
		.map((entry) => normalizeModel(entry, lookupCatalogModel(catalog, entry), normalized))
		.filter((model): model is NormalizedModel => model !== undefined)
		.sort((a, b) => a.id.localeCompare(b.id));
	if (models.length === 0) throw new Error(`No LiteLLM chat models discovered from ${modelsUrl}`);
	return {
		providerID: "litellm",
		providerName: normalized.providerName,
		baseUrl: endpointBaseUrl(normalized.baseUrl, modelsUrl),
		apiKeyEnv: normalized.apiKeyEnv,
		models,
	};
}

export function toV2Provider(discovery: DiscoveredLiteLLM) {
	return {
		id: discovery.providerID,
		name: discovery.providerName,
		integrationID: "litellm",
		api: {
			type: "aisdk" as const,
			package: "@ai-sdk/openai-compatible",
			url: discovery.baseUrl,
		},
		models: discovery.models.map((model) => toV2Model(model, discovery.baseUrl)),
	};
}

export function toV1ProviderConfig(discovery: DiscoveredLiteLLM) {
	return {
		name: discovery.providerName,
		env: [discovery.apiKeyEnv],
		npm: "@ai-sdk/openai-compatible",
		api: discovery.baseUrl,
		options: {
			baseURL: discovery.baseUrl,
		},
		models: Object.fromEntries(discovery.models.map((model) => [model.id, toV1Model(model, discovery.baseUrl)])),
	};
}

export function classifyRoute(entry: LiteLLMModelEntry, match: CatalogModelSnapshot | undefined, options?: LiteLLMOptions): RouteKind {
	const normalized = normalizeOptions(options);
	return classifyLiteLLMRoute(entry, {
		match,
		routeOverrides: normalized.routeOverrides,
	});
}

async function discover(options: ReturnType<typeof normalizeOptions>, catalog?: CatalogSnapshot): Promise<DiscoveredLiteLLM> {
	const headers = buildHeaders(options);
	const modelPayload = await fetchModels(modelUrls(options.baseUrl, options.modelsUrl), headers);
	const models = modelPayload.entries
		.map((entry) => normalizeModel(entry, lookupCatalogModel(catalog, entry), options))
		.filter((model): model is NormalizedModel => model !== undefined)
		.sort((a, b) => a.id.localeCompare(b.id));
	if (models.length === 0) throw new Error(`No LiteLLM chat models discovered from ${modelPayload.modelsUrl}`);
	return {
		providerID: "litellm",
		providerName: options.providerName,
		baseUrl: endpointBaseUrl(options.baseUrl, modelPayload.modelsUrl),
		apiKeyEnv: options.apiKeyEnv,
		models,
	};
}

function toV2Model(model: NormalizedModel, baseUrl: string): V2Model {
	const result: V2Model = {
		id: model.id,
		name: model.name,
		api: {
			id: model.id,
			type: "aisdk",
			package: model.route === "responses" ? "@ai-sdk/openai" : "@ai-sdk/openai-compatible",
			url: baseUrl,
			settings: {},
		},
		capabilities: {
			temperature: model.capabilities.temperature ?? false,
			reasoning: model.capabilities.reasoning ?? false,
			attachment: model.capabilities.attachment ?? false,
			tools: model.capabilities.tools ?? false,
			input: model.capabilities.input,
			output: model.capabilities.output,
			interleaved: model.capabilities.interleaved ?? false,
		},
		cost: costToV2(model.cost),
		limit: model.limit,
		variants: Object.entries(model.variants).map(([id, body]) => toV2Variant(id, body)),
		status: model.status ?? "active",
		enabled: true,
	};
	if (model.family) result.family = model.family;
	if (model.releaseDate) result.released = Date.parse(model.releaseDate) || 0;
	return result;
}

function toV1Model(model: NormalizedModel, baseUrl: string) {
	const result: Record<string, unknown> = {
		id: model.id,
		name: model.name,
		temperature: model.capabilities.temperature ?? false,
		reasoning: model.capabilities.reasoning ?? false,
		attachment: model.capabilities.attachment ?? false,
		tool_call: model.capabilities.tools ?? false,
		modalities: {
			input: model.capabilities.input,
			output: model.capabilities.output,
		},
		cost: model.cost,
		limit: model.limit,
		variants: model.variants,
		status: model.status ?? "active",
	};
	if (model.family) result.family = model.family;
	if (model.releaseDate) result.release_date = model.releaseDate;
	if (model.capabilities.interleaved) result.interleaved = model.capabilities.interleaved;
	if (model.route === "responses") {
		result.provider = {
			npm: "@ai-sdk/openai",
			api: baseUrl,
		};
	}
	return result;
}

function toV2Variant(id: string, body: Record<string, unknown>) {
	return {
		id,
		headers: {},
		body,
		generation: {},
	};
}

function buildHeaders(options: ReturnType<typeof normalizeOptions>) {
	const headers = { ...options.headers };
	const apiKey = process.env[options.apiKeyEnv] || readKeyFile(options.keyFile);
	if (!apiKey) return headers;
	if (!headers.Authorization) headers.Authorization = `Bearer ${apiKey}`;
	return headers;
}

function normalizeModel(entry: LiteLLMModelEntry, catalogModel: CatalogModelSnapshot | undefined, options: ReturnType<typeof normalizeOptions>): NormalizedModel | undefined {
	const id = entryID(entry);
	if (!id || isEmbeddingModel(id, entry)) return;
	const info = modelInfo(entry);
	const releaseDate = inferReleaseDate(id, info, catalogModel);
	const route = classifyLiteLLMRoute(entry, {
		match: catalogModel,
		routeOverrides: options.routeOverrides,
	});
	const cost = modelCost(info, catalogModel);
	const input = inputModalities(info, catalogModel, options);
	const output = outputModalities(info, catalogModel);
	const reasoning = mergeCapability(info.supports_reasoning, catalogModel, "reasoning");
	return {
		id,
		name: entry.name ?? catalogModel?.name ?? friendlyName(id),
		family: catalogModel?.family,
		releaseDate,
		status: catalogModel?.status,
		route,
		capabilities: {
			temperature: temperatureCapability(id, info, catalogModel),
			reasoning,
			attachment: attachmentCapability(info, catalogModel),
			tools: mergeCapability(info.supports_function_calling, catalogModel, "tools"),
			input,
			output,
			interleaved: catalogModel?.capabilities?.interleaved,
		},
		cost,
		limit: {
			context: info.max_input_tokens ?? entry.max_input_tokens ?? info.max_tokens ?? entry.context_window ?? entry.max_tokens ?? catalogModel?.limit?.context ?? options.defaults.context,
			input: info.max_input_tokens ?? entry.max_input_tokens ?? catalogModel?.limit?.input,
			output: info.max_output_tokens ?? entry.max_output_tokens ?? catalogModel?.limit?.output ?? options.defaults.output,
		},
		variants: normalizedVariants(catalogModel?.variants, route, reasoning, id, releaseDate),
	} satisfies NormalizedModel;
}

async function fetchModels(urls: string[], headers: Record<string, string>): Promise<{ entries: LiteLLMModelEntry[]; modelsUrl: string }> {
	let lastError: Error | undefined;
	for (const url of urls) {
		try {
			const response = await fetch(url, { headers, signal: AbortSignal.timeout(modelDiscoveryTimeoutMs) });
			if (!response.ok) {
				lastError = new Error(`GET ${url} failed with ${response.status} ${response.statusText}`);
				continue;
			}
			const payload = (await response.json()) as LiteLLMModelsPayload;
			if (!Array.isArray(payload.data)) {
				lastError = new Error(`GET ${url} returned no data array`);
				continue;
			}
			return { entries: payload.data, modelsUrl: url };
		} catch (error) {
			if (isAbortOrTimeoutError(error)) {
				lastError = new Error(`GET ${url} timed out after ${modelDiscoveryTimeoutMs}ms`);
				continue;
			}
			lastError = error instanceof Error ? error : new Error(String(error));
		}
	}
	throw lastError ?? new Error("Model discovery failed");
}

function isAbortOrTimeoutError(error: unknown) {
	return error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError");
}

function modelUrls(baseUrl: string, modelsUrl?: string) {
	if (modelsUrl) return [modelsUrl];
	if (baseUrl.endsWith("/v1")) return [`${baseUrl}/model/info`, `${baseUrl}/models`];
	return [`${baseUrl}/model/info`, `${baseUrl}/v1/model/info`, `${baseUrl}/v1/models`, `${baseUrl}/models`];
}

function endpointBaseUrl(baseUrl: string, modelsUrl: string) {
	const normalized = normalizeUrl(modelsUrl);
	if (normalized.endsWith("/models")) return normalized.slice(0, -"/models".length);
	return baseUrl.endsWith("/v1") ? baseUrl : `${baseUrl}/v1`;
}

function lookupCatalogModel(catalog: CatalogSnapshot | undefined, entry: LiteLLMModelEntry) {
	if (!catalog) return;
	const candidates = matchCandidates(entry);
	const providers = [...catalog.providers]
		.filter((provider) => provider.id !== "litellm")
		.sort((a, b) => providerRank(a.id) - providerRank(b.id) || a.id.localeCompare(b.id));
	for (const candidate of candidates) {
		for (const provider of providers) {
			const model = provider.models.find((item) => item.id === candidate);
			if (model) return model;
		}
	}
}

function matchCandidates(entry: LiteLLMModelEntry) {
	const info = modelInfo(entry);
	const raw = [entryID(entry), entry.litellm_params?.model, info.base_model, stripProviderPrefix(entry.litellm_params?.model), stripProviderPrefix(info.base_model)].filter((item): item is string => Boolean(item));
	const candidates: string[] = [];
	for (const candidate of raw) {
		for (const value of [candidate, canonicalModelID(candidate)]) {
			if (value && !candidates.includes(value)) candidates.push(value);
		}
	}
	return candidates;
}

function providerRank(providerID: string) {
	const rank = canonicalProviderOrder.indexOf(providerID);
	return rank === -1 ? canonicalProviderOrder.length : rank;
}

function getMode(entry: LiteLLMModelEntry) {
	return modelInfo(entry).mode ?? entry.mode ?? undefined;
}

function isEmbeddingModel(id: string, entry: LiteLLMModelEntry) {
	return id.toLowerCase().includes("embedding") || getMode(entry) === "embedding";
}

function inputModalities(info: LiteLLMModelInfo, catalogModel: CatalogModelSnapshot | undefined, options: ReturnType<typeof normalizeOptions>): Modality[] {
	const input: Modality[] = ["text"];
	if (info.supports_vision) input.push("image");
	if (info.supports_pdf_input) input.push("pdf");
	if (info.supports_audio_input) input.push("audio");
	if (input.length > 1) return input;
	return catalogModel?.capabilities?.input ?? options.defaults.input;
}

function outputModalities(info: LiteLLMModelInfo, catalogModel: CatalogModelSnapshot | undefined): Modality[] {
	const output: Modality[] = ["text"];
	if (info.supports_audio_output) output.push("audio");
	if (output.length > 1) return output;
	return catalogModel?.capabilities?.output ?? output;
}

function attachmentCapability(info: LiteLLMModelInfo, catalogModel: CatalogModelSnapshot | undefined) {
	if (info.supports_vision !== undefined || info.supports_pdf_input !== undefined || info.supports_audio_input !== undefined) {
		return Boolean(info.supports_vision || info.supports_pdf_input || info.supports_audio_input);
	}
	return catalogModel?.capabilities?.attachment;
}

function temperatureCapability(id: string, info: LiteLLMModelInfo, catalogModel: CatalogModelSnapshot | undefined) {
	const litellm = Array.isArray(info.supported_openai_params) ? info.supported_openai_params.includes("temperature") : undefined;
	if (canonicalModelID(id).toLowerCase().startsWith("claude") || canonicalModelID(id).toLowerCase().startsWith("gpt")) {
		return catalogModel?.capabilities?.temperature ?? litellm;
	}
	return litellm ?? catalogModel?.capabilities?.temperature;
}

function mergeCapability(value: boolean | null | undefined, catalogModel: CatalogModelSnapshot | undefined, key: "reasoning" | "tools") {
	if (value !== undefined && value !== null) return Boolean(value);
	return key === "reasoning" ? catalogModel?.capabilities?.reasoning : catalogModel?.capabilities?.tools;
}

function modelCost(info: LiteLLMModelInfo, catalogModel: CatalogModelSnapshot | undefined) {
	const cost = compactCost({
		input: perMillion(info.input_cost_per_token),
		output: perMillion(info.output_cost_per_token),
		cache_read: perMillion(info.cache_read_input_token_cost),
		cache_write: perMillion(info.cache_creation_input_token_cost),
	});
	return cost ?? catalogModel?.cost;
}

function costToV2(cost: NormalizedModel["cost"]) {
	if (!cost) return [];
	const base = {
		input: cost.input ?? 0,
		output: cost.output ?? 0,
		cache: { read: cost.cache_read ?? 0, write: cost.cache_write ?? 0 },
	};
	if (!cost.context_over_200k) return [base];
	return [
		base,
		{
			tier: { type: "context", size: 200_000 },
			input: cost.context_over_200k.input ?? 0,
			output: cost.context_over_200k.output ?? 0,
			cache: { read: cost.context_over_200k.cache_read ?? 0, write: cost.context_over_200k.cache_write ?? 0 },
		},
	];
}

function compactCost(cost: NonNullable<NormalizedModel["cost"]>) {
	return Object.values(cost).some((value) => typeof value === "number" && value !== 0) ? cost : undefined;
}

function perMillion(value?: number) {
	return typeof value === "number" ? Math.round(value * COST_MULTIPLIER * 10_000) / 10_000 : undefined;
}

function normalizedVariants(catalogVariants: CatalogModelSnapshot["variants"] | undefined, route: RouteKind, reasoning: boolean | undefined, id: string, releaseDate?: string) {
	if (catalogVariants && Object.keys(catalogVariants).length > 0) return catalogVariants;
	if (!reasoning) return {};
	return route === "responses" ? gptReasoningVariants(canonicalModelID(id).toLowerCase().replaceAll(".", "-"), releaseDate) : chatReasoningVariants(id);
}

function chatReasoningVariants(id: string) {
	const canonical = canonicalModelID(id).toLowerCase().replaceAll(".", "-");
	if (isAdaptiveClaudeModel(canonical)) return claudeReasoningVariants(canonical);
	return {
		low: { reasoning_effort: "low" },
		medium: { reasoning_effort: "medium" },
		high: { reasoning_effort: "high" },
	};
}

function isAdaptiveClaudeModel(canonical: string) {
	const match = canonical.match(/^claude-(opus|sonnet)-4-(\d+)$/);
	return Boolean(match && Number(match[2]) >= 6);
}

function claudeReasoningVariants(canonical: string) {
	const efforts = canonical.startsWith("claude-opus-4-7") ? ["low", "medium", "high", "xhigh", "max"] : ["low", "medium", "high", "max"];
	const thinking: Record<string, unknown> = { type: "adaptive" };
	if (canonical.startsWith("claude-opus-4-7")) thinking.display = "summarized";
	return Object.fromEntries(efforts.map((effort) => [`adaptive-${effort}`, { thinking, output_config: { effort } }]));
}

function gptReasoningVariants(canonical: string, releaseDate?: string) {
	if (canonical === "gpt-5-pro") return {};
	const efforts = ["low", "medium", "high"];
	if (canonical.includes("codex")) {
		if (/\bgpt-5-[23]-codex\b/.test(canonical)) efforts.push("xhigh");
		return Object.fromEntries(efforts.map((effort) => [effort, gptVariantOptions(effort)]));
	}
	if (canonical.startsWith("gpt-5")) efforts.unshift("minimal");
	if (releaseDate && releaseDate >= "2025-11-13") efforts.unshift("none");
	if (releaseDate && releaseDate >= "2025-12-04") efforts.push("xhigh");
	return Object.fromEntries(efforts.map((effort) => [effort, gptVariantOptions(effort)]));
}

function gptVariantOptions(effort: string) {
	return {
		reasoningEffort: effort,
		reasoningSummary: "auto",
		include: ["reasoning.encrypted_content"],
	};
}

function inferReleaseDate(id: string, info: LiteLLMModelInfo, catalogModel: CatalogModelSnapshot | undefined) {
	return normalizeReleaseDate(info.release_date) ?? normalizeReleaseDate(info.releaseDate) ?? normalizeReleaseDate(catalogModel?.releaseDate) ?? splitDateSuffix(id).releaseDate;
}

function normalizeReleaseDate(value?: string) {
	if (!value) return;
	const trimmed = value.trim();
	if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
	const match = trimmed.match(/^(\d{4})(\d{2})(\d{2})$/);
	return match ? `${match[1]}-${match[2]}-${match[3]}` : undefined;
}

function friendlyName(id: string) {
	const split = splitDateSuffix(id);
	const words = split.baseID.split("-");
	const result: string[] = [];
	let i = 0;
	if (brandMap[words[0]?.toLowerCase()]) {
		result.push(brandMap[words[0].toLowerCase()]);
		i = 1;
	}
	while (i < words.length) {
		const word = words[i];
		const lower = word.toLowerCase();
		if (tierWords[lower]) {
			result.push(tierWords[lower]);
			i += 1;
			continue;
		}
		if (/^\d+(\.\d+)?$/.test(word)) {
			const next = words[i + 1];
			if (next && /^\d{1,2}$/.test(next) && !tierWords[next.toLowerCase()]) {
				result.push(`${word}.${next}`);
				i += 2;
				continue;
			}
			result.push(word);
			i += 1;
			continue;
		}
		result.push(`${word.slice(0, 1).toUpperCase()}${word.slice(1)}`);
		i += 1;
	}
	return `${result.join(" ")}${split.displayDate ? ` (${monthNames[split.displayDate.month]} ${split.displayDate.day})` : ""}`;
}

function catalogKey(catalog: CatalogSnapshot | undefined) {
	if (!catalog) return "";
	return catalog.providers
		.filter((provider) => provider.id !== "litellm")
		.map((provider) => `${provider.id}:${provider.models.map((model) => model.id).join(",")}`)
		.join("|");
}

function normalizeUrl(url: string) {
	return url.trim().replace(/\/+$/, "");
}

function expandHome(value: string) {
	return value.startsWith("~/") ? join(homedir(), value.slice(2)) : value;
}

function readKeyFile(filepath: string) {
	try {
		return existsSync(filepath) ? readFileSync(filepath, "utf8").trim() : undefined;
	} catch {
		return undefined;
	}
}
