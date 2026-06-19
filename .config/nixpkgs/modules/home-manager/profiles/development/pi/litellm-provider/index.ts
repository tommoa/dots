import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getModels } from "@earendil-works/pi-ai";

type InputKind = "text" | "image";

interface LiteLLMSettings {
	baseUrl?: string;
	modelsUrl?: string;
	apiKey?: string;
	headers?: Record<string, string>;
	authHeaderName?: string;
	sendBearerAuth?: boolean;
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
}

interface LiteLLMModelEntry {
	id?: string;
	name?: string;
	model_name?: string;
	model_group?: string;
	litellm_provider?: string | null;
	custom_llm_provider?: string | null;
	context_window?: number;
	max_tokens?: number;
	max_input_tokens?: number;
	max_output_tokens?: number;
	input_cost_per_token?: number;
	output_cost_per_token?: number;
	supports_reasoning?: boolean | null;
	supports_vision?: boolean | null;
	mode?: string | null;
	model_info?: {
		max_tokens?: number;
		max_input_tokens?: number;
		max_output_tokens?: number;
		input_cost_per_token?: number;
		output_cost_per_token?: number;
		supports_vision?: boolean | null;
		supports_reasoning?: boolean | null;
		mode?: string | null;
		litellm_provider?: string | null;
		custom_llm_provider?: string | null;
	};
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

function readSettings(): LiteLLMSettings | null {
	const settingsPath = join(getAgentDir(), "settings.json");
	if (!existsSync(settingsPath)) {
		warn(`Missing Pi settings file at ${settingsPath}; skipping provider registration.`);
		return null;
	}

	try {
		const raw = readFileSync(settingsPath, "utf8");
		const settings = JSON.parse(raw) as PiSettings;
		if (!settings.litellmProvider) {
			warn(`Missing "litellmProvider" in ${settingsPath}; skipping provider registration.`);
			return null;
		}
		return settings.litellmProvider;
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

function multiplyPerTokenCost(value: number | undefined): number {
	return typeof value === "number" ? value * 1_000_000 : 0;
}

function getEntryId(entry: LiteLLMModelEntry): string | undefined {
	return entry.id ?? entry.model_name ?? entry.model_group;
}

function getModelInfo(entry: LiteLLMModelEntry): LiteLLMModelEntry {
	return entry.model_info ?? entry;
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

function getModelApi(entry: LiteLLMModelEntry, builtInModel: ProviderModel | undefined): string {
	const mode = getModelMode(entry);
	if (mode === "responses") return "openai-responses";
	if (mode === "chat") return "openai-completions";
	if (builtInModel?.api === "openai-responses") return "openai-responses";
	return "openai-completions";
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
	if (input !== 0 || output !== 0) {
		return {
			input,
			output,
			cacheRead: 0,
			cacheWrite: 0,
		};
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

function toFallbackModel(entry: LiteLLMModelEntry, settings: LiteLLMSettings) {
	const id = getEntryId(entry);
	if (!id) return null;

	const modelInfo = getModelInfo(entry);
	const api = getModelApi(entry, undefined);

	return {
		id,
		name: entry.name ?? entry.model_name ?? id,
		api,
		reasoning: modelInfo.supports_reasoning === true,
		input: getModelInput(entry, undefined, settings),
		contextWindow: getContextWindow(entry, undefined, settings),
		maxTokens: getMaxTokens(entry, undefined, settings),
		cost: getModelCost(entry, undefined),
		compat: getModelCompat(api, undefined, settings),
	};
}

function toProviderModel(entry: LiteLLMModelEntry, settings: LiteLLMSettings) {
	const id = getEntryId(entry);
	if (!id || isEmbeddingModel(id, entry)) return null;

	const family = getModelFamily(id, entry);
	const builtInModel = family ? (builtInModels[family].get(id) as ProviderModel | undefined) : undefined;
	const modelInfo = getModelInfo(entry);

	if (builtInModel) {
		const api = getModelApi(entry, builtInModel);
		return {
			id: builtInModel.id,
			name: entry.name ?? builtInModel.name,
			api,
			reasoning: modelInfo.supports_reasoning ?? builtInModel.reasoning,
			input: getModelInput(entry, builtInModel, settings),
			cost: getModelCost(entry, builtInModel),
			contextWindow: getContextWindow(entry, builtInModel, settings),
			maxTokens: getMaxTokens(entry, builtInModel, settings),
			compat: getModelCompat(api, builtInModel, settings),
		};
	}

	return toFallbackModel(entry, settings);
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
			const response = await fetch(modelsUrl, { headers });
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
	const settings = readSettings();
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
