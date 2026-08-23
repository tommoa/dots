import type {
	CatalogModelSnapshot,
	CatalogSnapshot,
	DiscoveredLiteLLM,
	DiscoveredModel,
	ModelStatus,
} from "./discovery";

const canonicalProviderOrder = ["openai", "anthropic", "google", "opencode"];
const chatPackage = "@opencode-ai/ai/providers/openai-compatible";
const responsesPackage = "@opencode-ai/ai/providers/openai/responses";

export interface V2Variant {
	id: string;
	settings?: Record<string, unknown>;
	headers?: Record<string, string>;
	body?: Record<string, unknown>;
}

export interface V2Compatibility {
	reasoningField?: string;
	maxTokensField?: "max_completion_tokens" | "max_tokens";
	requireFinishReason?: boolean;
}

export interface V2CostTier {
	input: number;
	output: number;
	cache: {
		read: number;
		write: number;
	};
	tier?: {
		type: "context";
		size: number;
	};
}

export interface V2Model {
	id: string;
	modelID: string;
	providerID: "litellm";
	name: string;
	package: string;
	settings: {
		baseURL: string;
		provider: "litellm";
	};
	compatibility?: V2Compatibility;
	capabilities: {
		tools: boolean;
		input: string[];
		output: string[];
	};
	cost: V2CostTier[];
	limit: {
		context: number;
		input?: number;
		output: number;
	};
	variants: V2Variant[];
	time: {
		released: number;
	};
	status: ModelStatus;
	enabled: boolean;
	family?: string;
}

export interface V2Provider {
	id: "litellm";
	name: string;
	integrationID: "litellm";
	package: string;
	settings: {
		baseURL: string;
		provider: "litellm";
	};
	models: V2Model[];
}

interface V2CatalogModel
	extends Pick<
		V2Model,
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

interface V2CatalogProviderRecord {
	provider: { id: string };
	models: ReadonlyMap<string, unknown>;
}

interface V2CatalogMetadata {
	variants: V2Variant[];
	compatibility?: V2Compatibility;
	cost: V2CostTier[];
}

export interface V2CatalogSnapshot {
	discovery: CatalogSnapshot;
	readonly metadata: ReadonlyMap<string, V2CatalogMetadata>;
}

type V2ProviderDefinition = Omit<V2Provider, "models">;
type V2ProviderDraft = Omit<
	V2ProviderDefinition,
	"integrationID" | "settings"
> &
	Partial<Pick<V2ProviderDefinition, "integrationID" | "settings">>;

type V2ModelDraft = Omit<V2Model, "family" | "package" | "settings"> &
	Partial<Pick<V2Model, "family" | "package" | "settings">>;

export interface V2CatalogDraft {
	provider: {
		list(): V2CatalogProviderRecord[];
		update(providerID: string, update: (draft: V2ProviderDraft) => void): void;
	};
	model: {
		remove(providerID: string, modelID: string): void;
		update(
			providerID: string,
			modelID: string,
			update: (draft: V2ModelDraft) => void,
		): void;
	};
}

export interface V2CatalogReader {
	model: {
		list(): Promise<{ data: V2CatalogModel[] }>;
	};
}

export function toV2Provider(
	discovery: DiscoveredLiteLLM,
	catalog?: V2CatalogSnapshot,
): V2Provider {
	const metadata = catalog?.metadata;
	return {
		id: discovery.providerID,
		name: discovery.providerName,
		integrationID: "litellm",
		package: chatPackage,
		settings: { baseURL: discovery.baseUrl, provider: "litellm" },
		models: discovery.models.map((model) =>
			toV2Model(
				model,
				discovery.baseUrl,
				model.catalogModelID ? metadata?.get(model.catalogModelID) : undefined,
			),
		),
	};
}

export async function snapshotV2Catalog(
	catalog: V2CatalogReader,
): Promise<V2CatalogSnapshot> {
	return catalogSnapshotFromV2((await catalog.model.list()).data);
}

export function catalogSnapshotFromV2(
	models: V2CatalogModel[],
): V2CatalogSnapshot {
	const discovery = new Map<string, CatalogModelSnapshot>();
	const metadata = new Map<string, V2CatalogMetadata>();
	const sorted = models
		.filter((model) => model.providerID !== "litellm")
		.toSorted(
			(left, right) =>
				providerRank(left.providerID) - providerRank(right.providerID) ||
				left.providerID.localeCompare(right.providerID),
		);
	for (const model of sorted) {
		if (discovery.has(model.id)) continue;
		discovery.set(model.id, normalizeV2CatalogModel(model));
		metadata.set(model.id, {
			variants: model.variants,
			compatibility: model.compatibility,
			cost: model.cost,
		});
	}
	return { discovery, metadata };
}

export function syncLiteLLMCatalog(
	catalog: V2CatalogDraft,
	provider: V2Provider,
) {
	const { models, ...definition } = provider;
	catalog.provider.update(provider.id, (draft) =>
		Object.assign(draft, definition),
	);

	const modelIDs = new Set(models.map((model) => model.id));
	for (const modelID of litellmCatalogModelIDs(catalog)) {
		if (!modelIDs.has(modelID)) catalog.model.remove(provider.id, modelID);
	}
	for (const model of models)
		catalog.model.update(provider.id, model.id, (draft) =>
			Object.assign(draft, model),
		);
}

function toV2Model(
	model: DiscoveredModel,
	baseUrl: string,
	metadata?: V2CatalogMetadata,
): V2Model {
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
		cost: mergeV2Cost(metadata?.cost ?? [], model.cost),
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

function normalizeV2CatalogModel(model: V2CatalogModel): CatalogModelSnapshot {
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
		cost: normalizeV2Cost(model.cost),
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

function effectiveCostTiers(cost: DiscoveredModel["cost"]): V2CostTier[] {
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

function mergeV2Cost(
	catalog: V2CostTier[],
	effective: DiscoveredModel["cost"],
): V2CostTier[] {
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

function costTierIdentity(tier: V2CostTier) {
	return tier.tier ? `context:${tier.tier.size}` : "base";
}

function copyCostTier(tier: V2CostTier): V2CostTier {
	return {
		input: tier.input,
		output: tier.output,
		cache: { ...tier.cache },
		...(tier.tier ? { tier: { ...tier.tier } } : {}),
	};
}

function copyVariant(variant: V2Variant): V2Variant {
	return {
		id: variant.id,
		...(variant.settings ? { settings: { ...variant.settings } } : {}),
		...(variant.headers ? { headers: { ...variant.headers } } : {}),
		...(variant.body ? { body: { ...variant.body } } : {}),
	};
}

function normalizeV2Cost(cost: V2CostTier[]) {
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

function litellmCatalogModelIDs(catalog: V2CatalogDraft): string[] {
	const record = catalog.provider
		.list()
		.find((item) => item.provider.id === "litellm");
	return record ? [...record.models.keys()] : [];
}
