import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getModels } from "@earendil-works/pi-ai";
import {
	classifyLiteLLMRoute,
	proxyModelRoute,
	reasoningEfforts,
	type ProxyModel,
	entryID as getEntryId,
	modelInfo as getModelInfo,
	type LiteLLMModelEntry,
	type LiteLLMRouteOverrides,
} from "../../ai-providers/routing";

type InputKind = "text" | "image";

interface LiteLLMSettings {
	baseUrl?: string;
	modelsUrl?: string;
	apiKey?: string;
	headers?: Record<string, string>;
	authHeaderName?: string;
	sendBearerAuth?: boolean;
	routeOverrides?: LiteLLMRouteOverrides;
	defaults?: {
		input?: InputKind[];
		contextWindow?: number;
		maxTokens?: number;
	};
	providerCompat?: {
		supportsDeveloperRole?: boolean;
		supportsReasoningEffort?: boolean;
		maxTokensField?: "max_completion_tokens" | "max_tokens";
	};
}

interface PiSettings {
	litellmProvider?: LiteLLMSettings;
	cliProxyProvider?: { baseUrl: string };
}

interface LiteLLMModelsPayload {
	data?: LiteLLMModelEntry[];
}

type ModelFamily = "anthropic" | "openai" | "google";

type ProviderModel = ReturnType<typeof getModels>[number];

const providerName = "litellm";

const builtInModels = {
	anthropic: new Map(getModels("anthropic").map((model) => [model.id, model])),
	openai: new Map(getModels("openai").map((model) => [model.id, model])),
	google: new Map(getModels("google").map((model) => [model.id, model])),
};

function warn(message: string): void {
	console.warn(`[litellm-provider] ${message}`);
}

function normalizeUrl(url: string): string {
	return url.trim().replace(/\/+$/, "");
}

function getAgentDir(): string {
	return process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
}

function readSettings(): PiSettings | null {
	const settingsPath = join(getAgentDir(), "settings.json");
	if (!existsSync(settingsPath)) {
		warn(`Missing Pi settings file at ${settingsPath}; skipping provider registration.`);
		return null;
	}

	try {
		const raw = readFileSync(settingsPath, "utf8");
		const settings = JSON.parse(raw) as PiSettings;
		return settings;
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		warn(`Could not parse ${settingsPath}: ${message}`);
		return null;
	}
}

function resolveApiKey(configuredValue: string | undefined): { resolved?: string; providerValue?: string } {
	if (!configuredValue) return {};

	const value = configuredValue.trim();
	if (!value || value === "REPLACE_ME") return {};

	if (value.startsWith("env:")) {
		const envVar = value.slice(4).trim();
		return {
			resolved: process.env[envVar],
			providerValue: `$${envVar}`,
		};
	}

	return { resolved: value, providerValue: value };
}

function buildHeaders(
	settings: LiteLLMSettings,
	configuredHeaders: Record<string, string> | undefined,
	resolvedApiKey: string | undefined,
): Record<string, string> {
	const headers = { ...(configuredHeaders ?? {}) };
	if (!resolvedApiKey) return headers;

	const authHeaderName = settings.authHeaderName?.trim() || "x-litellm-api-key";
	if (authHeaderName && !headers[authHeaderName]) {
		headers[authHeaderName] = resolvedApiKey;
	}

	if ((settings.sendBearerAuth ?? true) && !headers.Authorization) {
		headers.Authorization = `Bearer ${resolvedApiKey}`;
	}
	return headers;
}

function multiplyPerTokenCost(value: number | string | undefined): number {
	const numeric = typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : undefined;
	return typeof numeric === "number" && Number.isFinite(numeric) ? numeric * 1_000_000 : 0;
}

function getModelMode(entry: LiteLLMModelEntry): string | undefined {
	return getModelInfo(entry).mode ?? entry.mode ?? undefined;
}

function isEmbeddingModel(id: string, entry: LiteLLMModelEntry): boolean {
	return id.toLowerCase().includes("embedding") || getModelMode(entry) === "embedding";
}

function getProviderHint(entry: LiteLLMModelEntry): string {
	const modelInfo = getModelInfo(entry);
	return (
		modelInfo.litellm_provider ??
		entry.litellm_provider ??
		modelInfo.custom_llm_provider ??
		entry.custom_llm_provider ??
		""
	).toLowerCase();
}

function getModelFamily(id: string, entry: LiteLLMModelEntry): ModelFamily | null {
	const normalizedId = id.toLowerCase();
	if (normalizedId.startsWith("claude-")) return "anthropic";
	if (normalizedId.startsWith("gemini-") || normalizedId.startsWith("gemma-")) return "google";
	if (normalizedId.startsWith("gpt-") || /^o\d/.test(normalizedId)) return "openai";

	const providerHint = getProviderHint(entry);
	if (providerHint.includes("anthropic")) return "anthropic";
	if (providerHint.includes("google") || providerHint.includes("language-models")) return "google";
	if (providerHint.includes("openai") || providerHint.includes("azure")) return "openai";
	return null;
}

function getModelApi(entry: LiteLLMModelEntry, builtInModel: ProviderModel | undefined, settings: LiteLLMSettings): string {
	const route = classifyLiteLLMRoute(entry, {
		match: { api: builtInModel?.api },
		routeOverrides: settings.routeOverrides,
	});
	return route === "responses" ? "openai-responses" : "openai-completions";
}

function getModelInput(
	entry: LiteLLMModelEntry,
	builtInModel: ProviderModel | undefined,
	settings: LiteLLMSettings,
): InputKind[] {
	const modelInfo = getModelInfo(entry);
	if (modelInfo.supports_vision === true) return ["text", "image"];
	if (modelInfo.supports_vision === false) return ["text"];
	return (builtInModel?.input as InputKind[] | undefined) ?? settings.defaults?.input ?? ["text"];
}

function getContextWindow(
	entry: LiteLLMModelEntry,
	builtInModel: ProviderModel | undefined,
	settings: LiteLLMSettings,
): number {
	const modelInfo = getModelInfo(entry);
	return (
		modelInfo.max_input_tokens ??
		entry.max_input_tokens ??
		modelInfo.max_tokens ??
		entry.context_window ??
		entry.max_tokens ??
		builtInModel?.contextWindow ??
		settings.defaults?.contextWindow ??
		128000
	);
}

function getMaxTokens(
	entry: LiteLLMModelEntry,
	builtInModel: ProviderModel | undefined,
	settings: LiteLLMSettings,
): number {
	const modelInfo = getModelInfo(entry);
	return (
		modelInfo.max_output_tokens ??
		entry.max_output_tokens ??
		builtInModel?.maxTokens ??
		settings.defaults?.maxTokens ??
		16384
	);
}

function getModelCost(entry: LiteLLMModelEntry, builtInModel: ProviderModel | undefined) {
	const modelInfo = getModelInfo(entry);
	const input = multiplyPerTokenCost(modelInfo.input_cost_per_token);
	const output = multiplyPerTokenCost(modelInfo.output_cost_per_token);
	const cacheRead = multiplyPerTokenCost(modelInfo.cache_read_input_token_cost);
	const cacheWrite = multiplyPerTokenCost(modelInfo.cache_creation_input_token_cost);
	if (input !== 0 || output !== 0 || cacheRead !== 0 || cacheWrite !== 0) {
		return { input, output, cacheRead, cacheWrite };
	}
	return builtInModel?.cost ?? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
}

function getModelCompat(api: string, builtInModel: ProviderModel | undefined, settings: LiteLLMSettings) {
	if (api === "openai-responses") {
		return {
			...(builtInModel?.api === api ? (builtInModel.compat ?? {}) : {}),
			supportsDeveloperRole: settings.providerCompat?.supportsDeveloperRole,
		};
	}
	return settings.providerCompat;
}

function toProviderModel(entry: LiteLLMModelEntry, settings: LiteLLMSettings) {
	const id = getEntryId(entry);
	const info = getModelInfo(entry);
	// Pi always exposes agent tools; explicitly tool-disabled models cannot be used.
	if (
		!id ||
		isEmbeddingModel(id, entry) ||
		info.supports_function_calling === false
	)
		return null;
	const family = getModelFamily(id, entry);
	const source = family ? builtInModels[family].get(id) : undefined;
	const api = getModelApi(entry, source, settings);
	const levels =
		typeof info.supports_reasoning === "boolean"
			? reasoningEfforts(info)
			: undefined;
	return {
		id,
		name: entry.name ?? source?.name ?? entry.model_name ?? id,
		api,
		...reasoningOptions(levels, source),
		input: getModelInput(entry, source, settings),
		cost: getModelCost(entry, source),
		contextWindow: getContextWindow(entry, source, settings),
		maxTokens: getMaxTokens(entry, source, settings),
		compat: getModelCompat(api, source, settings),
	};
}

function getModelUrls(baseUrl: string, explicitModelsUrl: string | undefined): string[] {
	if (explicitModelsUrl) return [normalizeUrl(explicitModelsUrl)];
	if (baseUrl.endsWith("/v1")) return [`${baseUrl}/model/info`, `${baseUrl}/models`];
	return [`${baseUrl}/model/info`, `${baseUrl}/v1/model/info`, `${baseUrl}/v1/models`, `${baseUrl}/models`];
}

function getProviderBaseUrl(baseUrl: string, modelsUrl: string): string {
	const normalizedModelsUrl = normalizeUrl(modelsUrl);
	if (normalizedModelsUrl.endsWith("/models")) {
		return normalizedModelsUrl.slice(0, -"/models".length);
	}
	return baseUrl.endsWith("/v1") ? baseUrl : `${baseUrl}/v1`;
}

async function fetchModels(
	modelsUrls: string[],
	headers: Record<string, string>,
): Promise<{ entries: LiteLLMModelEntry[]; modelsUrl: string }> {
	let lastError: Error | null = null;
	for (const modelsUrl of modelsUrls) {
		try {
			const response = await fetch(modelsUrl, { headers, signal: AbortSignal.timeout(10_000) });
			if (!response.ok) {
				lastError = new Error(`GET ${modelsUrl} failed with ${response.status} ${response.statusText}`);
				continue;
			}

			const payload = (await response.json()) as LiteLLMModelsPayload;
			if (!Array.isArray(payload.data)) {
				lastError = new Error(`GET ${modelsUrl} returned no data array`);
				continue;
			}

			return { entries: payload.data, modelsUrl };
		} catch (error) {
			lastError = error instanceof Error ? error : new Error(String(error));
		}
	}

	throw lastError ?? new Error("Model discovery failed");
}

export default async function registerLiteLLMProvider(pi: ExtensionAPI) {
	const allSettings = readSettings();
	if (allSettings?.cliProxyProvider) {
		await registerCliProxyProvider(pi, allSettings.cliProxyProvider);
		return;
	}
	const settings = allSettings?.litellmProvider;
	if (!settings?.baseUrl || settings.baseUrl.trim() === "REPLACE_ME") {
		warn(`Set "litellmProvider.baseUrl" in Pi settings to enable LiteLLM model discovery.`);
		return;
	}

	const baseUrl = normalizeUrl(settings.baseUrl);
	const { resolved: resolvedApiKey, providerValue: providerApiKey } = resolveApiKey(settings.apiKey);
	const headers = buildHeaders(settings, settings.headers, resolvedApiKey);
	const modelUrls = getModelUrls(baseUrl, settings.modelsUrl);

	let entries: LiteLLMModelEntry[];
	let modelsUrl: string;
	try {
		({ entries, modelsUrl } = await fetchModels(modelUrls, headers));
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		warn(`Model discovery failed: ${message}`);
		return;
	}
	const providerBaseUrl = getProviderBaseUrl(baseUrl, modelsUrl);

	const providerModels: ReturnType<typeof toProviderModel>[] = [];
	for (const entry of entries) {
		providerModels.push(toProviderModel(entry, settings));
	}

	pi.unregisterProvider(providerName);

	const models = providerModels
		.filter((model): model is NonNullable<typeof model> => model !== null)
		.sort((a, b) => a.id.localeCompare(b.id));

	if (models.length === 0) {
		warn(`No LiteLLM chat models discovered from ${modelsUrl}; skipping provider registration.`);
		return;
	}

	pi.registerProvider(providerName, {
		name: "LiteLLM",
		baseUrl: providerBaseUrl,
		apiKey: providerApiKey,
		headers,
		models,
	});
}

function reasoningOptions(
	levels: readonly string[] | undefined,
	source: ProviderModel | undefined,
) {
	// Unknown declarations inherit native metadata; an explicit empty list disables controls.
	if (levels === undefined) {
		return {
			reasoning: source?.reasoning ?? false,
			thinkingLevelMap: source?.thinkingLevelMap,
		};
	}
	return {
		reasoning: levels.length > 0,
		thinkingLevelMap: Object.fromEntries(
			["off", "minimal", "low", "medium", "high", "xhigh", "max"].map(
				(level) => {
					const effort = level === "off" ? "none" : level;
					if (levels.includes(effort)) return [level, effort];
					// Pi has no ultra control. Use its max slot only when max is absent.
					if (level === "max" && levels.includes("ultra"))
						return [level, "ultra"];
					return [level, null];
				},
			),
		),
	};
}

// CLIProxyAPI owns inventory, capabilities and authentication for every upstream.
async function registerCliProxyProvider(
	pi: ExtensionAPI,
	config: { baseUrl: string },
) {
	const baseUrl = normalizeUrl(config.baseUrl);
	let entries: ProxyModel[];
	try {
		const result = await fetchModels([`${baseUrl}/models?metadata=true`], {});
		if (
			result.entries.some(
				(entry) => typeof entry.id !== "string" || !entry.id.trim(),
			)
		) {
			throw new Error("Model listing has an invalid id");
		}
		entries = result.entries as ProxyModel[];
	} catch (error) {
		warn(`CLIProxyAPI model discovery failed: ${String(error)}`);
		return;
	}
	const models = [];
	for (const entry of entries) {
		const id = entry.id;
		if (!id) continue;
		const isCorporate = id.startsWith("ai-proxy/");
		const upstreamID = isCorporate ? id.slice("ai-proxy/".length) : id;
		if (/^gpt-image-|embedding/i.test(upstreamID)) continue;
		const family = getModelFamily(upstreamID, { id: upstreamID });
		// The proxy owns availability; Pi's bundled catalog only enriches metadata.
		const source = family ? builtInModels[family].get(upstreamID) : undefined;
		const api =
			proxyModelRoute(entry) === "responses"
				? "openai-responses"
				: "openai-completions";
		const input = entry.supportedInputModalities?.filter(
			(value): value is InputKind => value === "text" || value === "image",
		);
		models.push({
			id,
			name: entry.display_name ?? source?.name ?? id,
			api,
			...reasoningOptions(
				entry.thinking === undefined
					? undefined
					: (entry.thinking.levels ?? []),
				source,
			),
			input: input?.length ? input : (source?.input ?? ["text"]),
			contextWindow:
				entry.max_context_length ??
				entry.context_length ??
				source?.contextWindow ??
				128000,
			maxTokens: entry.max_completion_tokens ?? source?.maxTokens ?? 16384,
			cost: isCorporate
				? (source?.cost ?? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 })
				: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			// Native transport options are incompatible with the proxy's chat protocol.
			compat: source?.api === api ? source.compat : undefined,
		});
	}
	if (!models.length) {
		warn(
			"CLIProxyAPI has no supported chat models; skipping provider registration.",
		);
		return;
	}
	pi.registerProvider("cli_proxy_api", {
		name: "CLIProxyAPI",
		baseUrl,
		apiKey: "local",
		models,
	});
}
