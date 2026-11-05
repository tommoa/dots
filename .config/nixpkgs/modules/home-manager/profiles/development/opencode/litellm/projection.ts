import {
	canonicalModelID,
	classifyLiteLLMRoute,
	entryID,
	modelInfo,
	reasoningEfforts,
	stripProviderPrefix,
	type LiteLLMModelEntry,
	type LiteLLMModelInfo,
} from "../../ai-providers/routing";
import {
	toReasoningVariants,
	type ModelMetadata,
	type ModelCostTier,
} from "../models";
import type { NormalizedLiteLLMOptions, DiscoveredLiteLLM } from "./discovery";

type Modality = string;
type CatalogModel = ModelMetadata & { providerID: string; modelID: string };
export type Model = ModelMetadata & {
	modelID: string;
	providerID: "litellm";
};

export interface Provider {
	id: "litellm";
	name: string;
	activation: "enabled";
	integrationID: "litellm";
	package: string;
	settings: {
		baseURL: string;
		provider: "litellm";
		apiKey?: string;
		headers?: Record<string, string>;
	};
	models: Model[];
}

const canonicalProviderOrder = ["openai", "anthropic", "google", "opencode"];
const chatPackage = "@opencode/ai/providers/openai-compatible";
const responsesPackage = "@opencode/ai/providers/openai/responses";
const COST_MULTIPLIER = 1_000_000;

export function toProvider(
	discovery: DiscoveredLiteLLM,
	options: NormalizedLiteLLMOptions,
	nativeModels: CatalogModel[],
): Provider {
	// Keep native metadata in OpenCode's format; only selection precedence is indexed.
	const catalog = new Map<string, CatalogModel>();
	for (const model of nativeModels
		.filter(
			(model) =>
				model.providerID !== "litellm" && model.providerID !== "cli_proxy_api",
		)
		.toSorted(
			(left, right) =>
				providerRank(left.providerID) - providerRank(right.providerID) ||
				left.providerID.localeCompare(right.providerID),
		)) {
		if (!catalog.has(model.id)) catalog.set(model.id, model);
	}
	const models = [
		...new Map(
			discovery.entries
				.map((entry) =>
					projectModel(entry, lookupCatalogModel(catalog, entry), options),
				)
				.filter((model): model is Model => model !== undefined)
				.map((model) => [model.id, model] as const),
		).values(),
	].sort((left, right) => left.id.localeCompare(right.id));
	if (!models.length)
		throw new Error(
			`No LiteLLM chat models discovered from ${discovery.modelsUrl}`,
		);
	return {
		id: "litellm",
		name: options.providerName,
		activation: "enabled",
		integrationID: "litellm",
		package: chatPackage,
		settings: { baseURL: discovery.baseUrl, provider: "litellm" },
		models,
	};
}
function projectModel(
	entry: LiteLLMModelEntry,
	source: CatalogModel | undefined,
	options: NormalizedLiteLLMOptions,
): Model | undefined {
	const id = entryID(entry);
	if (!id || isEmbeddingModel(id, entry)) return;
	const info = modelInfo(entry);
	const route = classifyLiteLLMRoute(entry, {
		match: { providerPackage: source?.package },
		routeOverrides: options.routeOverrides,
	});
	const temperature = temperatureCapability(id, info, source);
	// Build fresh metadata so native endpoints, credentials and request variants
	// cannot leak into the LiteLLM transport.
	return {
		id,
		modelID: id,
		providerID: "litellm",
		name:
			entry.name?.trim() ||
			(source?.id === canonicalModelID(id) ? source.name : undefined) ||
			id,
		package: route === "responses" ? responsesPackage : chatPackage,
		...(source?.compatibility ? { compatibility: source.compatibility } : {}),
		capabilities: {
			tools:
				info.supports_function_calling ?? source?.capabilities.tools ?? false,
			input: inputModalities(info, source, options),
			output: outputModalities(info, source),
			...(temperature !== undefined ? { temperature } : {}),
		},
		cost: modelCost(info, source),
		limit: {
			context:
				info.max_input_tokens ??
				entry.max_input_tokens ??
				info.max_tokens ??
				entry.context_window ??
				entry.max_tokens ??
				source?.limit.context ??
				options.defaults.context,
			input:
				info.max_input_tokens ?? entry.max_input_tokens ?? source?.limit.input,
			output:
				info.max_output_tokens ??
				entry.max_output_tokens ??
				source?.limit.output ??
				options.defaults.output,
		},
		variants: toReasoningVariants(reasoningEfforts(info), route),
		time: source?.time ?? { released: 0 },
		status: source?.status ?? "active",
		enabled: true,
		family: source?.family,
	};
}

function lookupCatalogModel(
	catalog: ReadonlyMap<string, CatalogModel>,
	entry: LiteLLMModelEntry,
) {
	for (const candidate of matchCandidates(entry)) {
		const model = catalog.get(candidate);
		if (model) return model;
	}
}

function matchCandidates(entry: LiteLLMModelEntry) {
	const info = modelInfo(entry);
	const raw = [
		entryID(entry),
		entry.litellm_params?.model,
		info.base_model,
		stripProviderPrefix(entry.litellm_params?.model),
		stripProviderPrefix(info.base_model),
	].filter((item): item is string => Boolean(item));
	const candidates: string[] = [];
	for (const candidate of raw) {
		for (const value of [candidate, canonicalModelID(candidate)]) {
			if (value && !candidates.includes(value)) candidates.push(value);
		}
	}
	return candidates;
}

function getMode(entry: LiteLLMModelEntry) {
	return modelInfo(entry).mode ?? entry.mode ?? undefined;
}

function isEmbeddingModel(id: string, entry: LiteLLMModelEntry) {
	return (
		id.toLowerCase().includes("embedding") || getMode(entry) === "embedding"
	);
}

function inputModalities(
	info: LiteLLMModelInfo,
	catalogModel: CatalogModel | undefined,
	options: NormalizedLiteLLMOptions,
): Modality[] {
	const fallback = catalogModel?.capabilities.input ?? options.defaults.input;
	const input = fallback.filter(
		(modality) => !["image", "pdf", "audio"].includes(modality),
	);
	if (info.supports_vision ?? fallback.includes("image")) input.push("image");
	if (info.supports_pdf_input ?? fallback.includes("pdf")) input.push("pdf");
	if (info.supports_audio_input ?? fallback.includes("audio")) input.push("audio");
	return input;
}

function outputModalities(
	info: LiteLLMModelInfo,
	catalogModel: CatalogModel | undefined,
): Modality[] {
	const fallback = catalogModel?.capabilities.output ?? ["text"];
	const output = fallback.filter((modality) => modality !== "audio");
	if (info.supports_audio_output ?? fallback.includes("audio"))
		output.push("audio");
	return output;
}

function temperatureCapability(
	id: string,
	info: LiteLLMModelInfo,
	catalogModel: CatalogModel | undefined,
) {
	const litellm = Array.isArray(info.supported_openai_params)
		? info.supported_openai_params.includes("temperature")
		: undefined;
	if (
		canonicalModelID(id).toLowerCase().startsWith("claude") ||
		canonicalModelID(id).toLowerCase().startsWith("gpt")
	) {
		return catalogModel?.capabilities?.temperature ?? litellm;
	}
	return litellm ?? catalogModel?.capabilities?.temperature;
}

function modelCost(
	info: LiteLLMModelInfo,
	source: CatalogModel | undefined,
): ModelCostTier[] {
	const costs = structuredClone(source?.cost ?? []);
	const declared = {
		input: perMillion(info.input_cost_per_token),
		output: perMillion(info.output_cost_per_token),
		cacheRead: perMillion(info.cache_read_input_token_cost),
		cacheWrite: perMillion(info.cache_creation_input_token_cost),
	};
	// Missing or all-zero declarations use native prices. Nonzero declarations
	// replace the base rate while context tiers retain their native rates.
	if (
		!Object.values(declared).some(
			(value) => typeof value === "number" && value !== 0,
		)
	)
		return costs;
	const base = {
		input: declared.input ?? 0,
		output: declared.output ?? 0,
		cache: { read: declared.cacheRead ?? 0, write: declared.cacheWrite ?? 0 },
	};
	const updated = costs.map((tier) =>
		tier.tier === undefined
			? { ...base, cache: { ...base.cache } }
			: tier,
	);
	return costs.some((tier) => tier.tier === undefined)
		? updated
		: [base, ...updated];
}

function perMillion(value?: number | string) {
	const numeric =
		typeof value === "number"
			? value
			: typeof value === "string" && value.trim()
				? Number(value)
				: undefined;
	return typeof numeric === "number" && Number.isFinite(numeric)
		? Math.round(numeric * COST_MULTIPLIER * 10_000) / 10_000
		: undefined;
}

function providerRank(providerID: string) {
	const rank = canonicalProviderOrder.indexOf(providerID);
	return rank === -1 ? canonicalProviderOrder.length : rank;
}
