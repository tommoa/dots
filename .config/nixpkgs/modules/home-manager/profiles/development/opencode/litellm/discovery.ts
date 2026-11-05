import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { LiteLLMModelEntry } from "../../ai-providers/routing";

type Modality = string;

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

interface LiteLLMModelsPayload {
	data?: LiteLLMModelEntry[];
}

const defaultBaseUrl = "https://ai-proxy.infra.corp.arista.io";
const defaultApiKeyEnv = "LITELLM_API_KEY";
const modelDiscoveryTimeoutMs = 30_000;

export function warn(message: string) {
	console.warn(`[opencode-litellm] ${message}`);
}

export function normalizeOptions(options?: LiteLLMOptions) {
	const apiKeyEnv = options?.apiKeyEnv?.trim() || defaultApiKeyEnv;
	const keyFile = expandHome(options?.keyFile ?? "~/.config/ai-keys/litellm");
	return {
		baseUrl: normalizeUrl(options?.baseUrl ?? defaultBaseUrl),
		modelsUrl: options?.modelsUrl ? normalizeUrl(options.modelsUrl) : undefined,
		apiKeyEnv,
		keyFile,
		apiKey: process.env[apiKeyEnv]?.trim() || readKeyFile(keyFile),
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

export type NormalizedLiteLLMOptions = ReturnType<typeof normalizeOptions>;

export async function discoverLiteLLM(options: NormalizedLiteLLMOptions) {
	const payload = await fetchModels(
		modelUrls(options.baseUrl, options.modelsUrl),
		buildHeaders(options),
	);
	return {
		...payload,
		baseUrl: endpointBaseUrl(options.baseUrl, payload.modelsUrl),
	};
}

export type DiscoveredLiteLLM = Awaited<ReturnType<typeof discoverLiteLLM>>;

function buildHeaders(options: NormalizedLiteLLMOptions) {
	const headers = { ...options.headers };
	const apiKey = options.apiKey;
	if (!apiKey) return headers;
	if (!headers.Authorization) headers.Authorization = `Bearer ${apiKey}`;
	return headers;
}

async function fetchModels(
	urls: string[],
	headers: Record<string, string>,
): Promise<{ entries: LiteLLMModelEntry[]; modelsUrl: string }> {
	let lastError: Error | undefined;
	for (const url of urls) {
		try {
			const response = await fetch(url, {
				headers,
				signal: AbortSignal.timeout(modelDiscoveryTimeoutMs),
			});
			if (!response.ok) {
				lastError = new Error(
					`GET ${url} failed with ${response.status} ${response.statusText}`,
				);
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
				lastError = new Error(
					`GET ${url} timed out after ${modelDiscoveryTimeoutMs}ms`,
				);
				continue;
			}
			lastError = error instanceof Error ? error : new Error(String(error));
		}
	}
	throw lastError ?? new Error("Model discovery failed");
}

function isAbortOrTimeoutError(error: unknown) {
	return (
		error instanceof Error &&
		(error.name === "AbortError" || error.name === "TimeoutError")
	);
}

function modelUrls(baseUrl: string, modelsUrl?: string) {
	if (modelsUrl) return [modelsUrl];
	if (baseUrl.endsWith("/v1"))
		return [`${baseUrl}/model/info`, `${baseUrl}/models`];
	return [
		`${baseUrl}/model/info`,
		`${baseUrl}/v1/model/info`,
		`${baseUrl}/v1/models`,
		`${baseUrl}/models`,
	];
}

function endpointBaseUrl(baseUrl: string, modelsUrl: string) {
	const normalized = normalizeUrl(modelsUrl);
	if (normalized.endsWith("/models"))
		return normalized.slice(0, -"/models".length);
	return baseUrl.endsWith("/v1") ? baseUrl : `${baseUrl}/v1`;
}

function normalizeUrl(url: string) {
	return url.trim().replace(/\/+$/, "");
}

function expandHome(value: string) {
	return value.startsWith("~/") ? join(homedir(), value.slice(2)) : value;
}

function readKeyFile(filepath: string) {
	try {
		return existsSync(filepath)
			? readFileSync(filepath, "utf8").trim()
			: undefined;
	} catch {
		return undefined;
	}
}
