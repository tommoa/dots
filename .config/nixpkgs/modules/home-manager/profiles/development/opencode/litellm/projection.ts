import type {
	CatalogModelSnapshot,
	CatalogSnapshot as DiscoveryCatalogSnapshot,
	DiscoveredLiteLLM,
	DiscoveredModel,
} from "./discovery";

import type {
	ModelMetadata,
	ModelCostTier,
	ModelVariant,
	ModelCompatibility,
} from "../models";

const canonicalProviderOrder = ["openai", "anthropic", "google", "opencode"];
const chatPackage = "@opencode/ai/providers/openai-compatible";
const responsesPackage = "@opencode/ai/providers/openai/responses";

export interface Model extends ModelMetadata {
	modelID: string;
	providerID: "litellm";
	settings: {
		baseURL: string;
		provider: "litellm";
	};
}

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

interface CatalogModel
	extends Pick<
		Model,
		| "id"
		| "modelID"
		| "name"
		| "family"
		| "compatibility"
		| "capabilities"
		| "cost"
		| "limit"
		| "variants"
		| "time"
		| "status"
		| "enabled"
	> {
	providerID: string;
	package: string;
}

interface CatalogMetadata {
	variants: ModelVariant[];
	compatibility?: ModelCompatibility;
	cost: ModelCostTier[];
}

export interface CatalogSnapshot {
	discovery: DiscoveryCatalogSnapshot;
	readonly metadata: ReadonlyMap<string, CatalogMetadata>;
}

export function toProvider(
	discovery: DiscoveredLiteLLM,
	catalog?: CatalogSnapshot,
): Provider {
	const metadata = catalog?.metadata;
	return {
		id: discovery.providerID,
		name: discovery.providerName,
		activation: "enabled",
		integrationID: "litellm",
		package: chatPackage,
		settings: { baseURL: discovery.baseUrl, provider: "litellm" },
		models: discovery.models.map((model) =>
			toModel(
				model,
				discovery.baseUrl,
				model.catalogModelID ? metadata?.get(model.catalogModelID) : undefined,
			),
		),
	};
}

export function catalogSnapshotFromModels(
	models: CatalogModel[],
): CatalogSnapshot {
	const discovery = new Map<string, CatalogModelSnapshot>();
	const metadata = new Map<string, CatalogMetadata>();
	const sorted = models
		.filter((model) => model.providerID !== "litellm")
		.toSorted(
			(left, right) =>
				providerRank(left.providerID) - providerRank(right.providerID) ||
				left.providerID.localeCompare(right.providerID),
		);
	for (const model of sorted) {
		if (discovery.has(model.id)) continue;
		discovery.set(model.id, normalizeCatalogModel(model));
		metadata.set(model.id, {
			variants: model.variants,
			compatibility: model.compatibility,
			cost: model.cost,
		});
	}
	return { discovery, metadata };
}

function toModel(
	model: DiscoveredModel,
	baseUrl: string,
	metadata?: CatalogMetadata,
): Model {
	return {
		id: model.id,
		modelID: model.id,
		providerID: "litellm",
		name: model.name,
		package: model.route === "responses" ? responsesPackage : chatPackage,
		settings: { baseURL: baseUrl, provider: "litellm" },
		...(metadata?.compatibility
			? { compatibility: metadata.compatibility }
			: {}),
		capabilities: {
			tools: model.capabilities.tools ?? false,
			input: model.capabilities.input,
			output: model.capabilities.output,
		},
		cost: mergeCost(metadata?.cost ?? [], model.cost),
		limit: model.limit,
		variants: metadata?.variants.length
			? metadata.variants.map(copyVariant)
			: Object.entries(model.variants).map(([id, settings]) => ({
					id,
					settings,
				})),
		time: {
			released: model.releaseDate ? Date.parse(model.releaseDate) || 0 : 0,
		},
		status: model.status ?? "active",
		enabled: true,
		family: model.family,
	};
}

function normalizeCatalogModel(model: CatalogModel): CatalogModelSnapshot {
	const input = model.capabilities.input;
	return {
		id: model.id,
		name: model.name,
		family: model.family,
		releaseDate:
			model.time.released > 0
				? new Date(model.time.released).toISOString().slice(0, 10)
				: undefined,
		status: model.status,
		providerPackage: model.package,
		capabilities: {
			tools: model.capabilities.tools,
			attachment: input.some((modality) => modality !== "text"),
			input,
			output: model.capabilities.output,
		},
		cost: normalizeCost(model.cost),
		limit: model.limit,
		variants: model.variants.length
			? Object.fromEntries(
					model.variants.map((variant) => [
						variant.id,
						variant.settings ?? variant.body ?? {},
					]),
				)
			: undefined,
	};
}

function effectiveCostTiers(cost: DiscoveredModel["cost"]): ModelCostTier[] {
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
			cache: {
				read: cost.context_over_200k.cache_read ?? 0,
				write: cost.context_over_200k.cache_write ?? 0,
			},
		},
	];
}

function mergeCost(
	catalog: ModelCostTier[],
	effective: DiscoveredModel["cost"],
): ModelCostTier[] {
	const overrides = effectiveCostTiers(effective);
	if (overrides.length === 0) return catalog.map(copyCostTier);
	const overridesByTier = new Map(
		overrides.map((tier) => [costTierIdentity(tier), tier]),
	);
	const catalogTiers = new Set(catalog.map(costTierIdentity));
	const merged = catalog.map(
		(tier) => overridesByTier.get(costTierIdentity(tier)) ?? copyCostTier(tier),
	);
	const missing = overrides.filter(
		(tier) => !catalogTiers.has(costTierIdentity(tier)),
	);
	return [
		...missing.filter((tier) => tier.tier === undefined),
		...merged,
		...missing.filter((tier) => tier.tier !== undefined),
	];
}

function costTierIdentity(tier: ModelCostTier) {
	return tier.tier ? `context:${tier.tier.size}` : "base";
}

function copyCostTier(tier: ModelCostTier): ModelCostTier {
	return {
		input: tier.input,
		output: tier.output,
		cache: { ...tier.cache },
		...(tier.tier ? { tier: { ...tier.tier } } : {}),
	};
}

function copyVariant(variant: ModelVariant): ModelVariant {
	return {
		id: variant.id,
		...(variant.settings ? { settings: { ...variant.settings } } : {}),
		...(variant.headers ? { headers: { ...variant.headers } } : {}),
		...(variant.body ? { body: { ...variant.body } } : {}),
	};
}

function normalizeCost(cost: ModelCostTier[]) {
	const base = cost.find((tier) => tier.tier === undefined);
	if (!base) return undefined;
	const contextOver200k = cost.find(
		(tier) => tier.tier?.type === "context" && tier.tier.size === 200_000,
	);
	const normalized = {
		input: base.input,
		output: base.output,
		cache_read: base.cache.read,
		cache_write: base.cache.write,
	};
	if (!contextOver200k) return normalized;
	return {
		...normalized,
		context_over_200k: {
			input: contextOver200k.input,
			output: contextOver200k.output,
			cache_read: contextOver200k.cache.read,
			cache_write: contextOver200k.cache.write,
		},
	};
}

function providerRank(providerID: string) {
	const rank = canonicalProviderOrder.indexOf(providerID);
	return rank === -1 ? canonicalProviderOrder.length : rank;
}
