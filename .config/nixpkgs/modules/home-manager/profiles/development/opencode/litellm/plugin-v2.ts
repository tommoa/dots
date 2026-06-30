import { discoverLiteLLM, toV1ProviderConfig, toV2Provider, warn, type CatalogSnapshot, type LiteLLMOptions } from "./discovery";

export default {
	id: "litellm",
	server(_input, options) {
		const pluginOptions = (options ?? {}) as LiteLLMOptions;
		return {
			async config(config) {
				try {
					const provider = toV1ProviderConfig(await discoverLiteLLM(pluginOptions));
					config.provider ??= {};
					config.provider.litellm = mergeProviderConfig(provider, config.provider.litellm);
				} catch (error) {
					warn(`Model discovery failed: ${error instanceof Error ? error.message : String(error)}`);
				}
			},
		};
	},
	async setup(ctx) {
		const options = (ctx.options ?? {}) as LiteLLMOptions;
		const responsesModelIDs = new Set<string>();

		await ctx.aisdk.language((event) => {
			routeLiteLLMResponsesModel(event, responsesModelIDs);
		});

		await ctx.integration.transform((draft) => {
			draft.update("litellm", (integration) => {
				integration.name = options.providerName ?? "LiteLLM";
			});
			draft.method.update({
				integrationID: "litellm",
				method: { type: "env", names: [options.apiKeyEnv ?? "LITELLM_API_KEY"] },
			});
			draft.method.update({
				integrationID: "litellm",
				method: { type: "key", label: "LiteLLM API key" },
			});
		});

		await ctx.catalog.transform(async (catalog) => {
			const snapshot = snapshotCatalog(catalog);
			let provider: ReturnType<typeof toV2Provider> | undefined;
			try {
				provider = toV2Provider(await discoverLiteLLM(options, snapshot));
			} catch (error) {
				warn(`Model discovery failed: ${error instanceof Error ? error.message : String(error)}`);
			}
			syncCatalogResponsesModelIDs(responsesModelIDs, catalog, provider);

			catalog.provider.update("litellm", (draft) => {
				draft.name = provider?.name ?? "LiteLLM";
				draft.integrationID = "litellm";
				draft.api = provider?.api ?? {
					type: "aisdk",
					package: "@ai-sdk/openai-compatible",
					url: normalizeBaseUrl(options.baseUrl ?? "https://ai-proxy.infra.corp.arista.io"),
				};
			});

			syncLiteLLMModels(catalog, provider);
		});
	},
};

function mergeProviderConfig(discovered, configured) {
	if (!configured) return discovered;
	return {
		...discovered,
		...configured,
		env: configured.env ?? discovered.env,
		npm: configured.npm ?? discovered.npm,
		api: configured.api ?? discovered.api,
		options: {
			...discovered.options,
			...(configured.options ?? {}),
		},
		models: {
			...discovered.models,
			...(configured.models ?? {}),
		},
	};
}

export function routeLiteLLMResponsesModel(event, responsesModelIDs: Set<string>) {
	if (event.model.providerID !== "litellm") return;
	if (!responsesModelIDs.has(String(event.model.id))) return;
	if (typeof event.sdk.responses !== "function") {
		warn(`Responses route unavailable for ${event.model.id}`);
		return;
	}
	event.language = event.sdk.responses(event.model.api.id);
}

export function syncResponsesModelIDs(responsesModelIDs: Set<string>, models) {
	responsesModelIDs.clear();
	for (const model of models) {
		const sdkPackage = model.api?.package ?? model.api?.npm;
		if (sdkPackage === "@ai-sdk/openai") responsesModelIDs.add(String(model.id));
	}
}

export function syncCatalogResponsesModelIDs(responsesModelIDs: Set<string>, catalog, provider: ReturnType<typeof toV2Provider> | undefined) {
	syncResponsesModelIDs(responsesModelIDs, provider?.models ?? litellmCatalogModels(catalog));
}

export function syncLiteLLMModels(catalog, provider: ReturnType<typeof toV2Provider> | undefined) {
	if (!provider) return;

	const modelIDs = new Set(provider.models.map((model) => model.id as string));
	for (const model of litellmCatalogModels(catalog)) {
		if (!modelIDs.has(model.id)) catalog.model.remove("litellm", model.id);
	}
	for (const model of provider.models) {
		catalog.model.update("litellm", model.id as string, (draft) => {
			if (typeof model.name === "string") draft.name = model.name;
			if (typeof model.family === "string") draft.family = model.family;
			if (model.api !== undefined) draft.api = { ...draft.api, ...model.api };
			if (model.capabilities !== undefined) draft.capabilities = model.capabilities as typeof draft.capabilities;
			if (Array.isArray(model.cost)) draft.cost = model.cost as typeof draft.cost;
			if (model.limit !== undefined) draft.limit = { ...draft.limit, ...model.limit } as typeof draft.limit;
			if (Array.isArray(model.variants)) draft.variants = model.variants as typeof draft.variants;
			if (typeof model.released === "number") draft.time.released = model.released;
			draft.status = "active";
			draft.enabled = true;
		});
	}
}

export function snapshotCatalog(catalog): CatalogSnapshot {
	const seen = new Set<string>();
	const providers = catalog.provider
		.list()
		.map((record) => normalizeProviderSnapshot(record))
		.filter((provider) => {
			if (!provider.id || provider.id === "litellm" || seen.has(provider.id)) return false;
			seen.add(provider.id);
			return true;
		});
	return { providers };
}

function normalizeProviderSnapshot(record) {
	const providerApi = record?.provider?.api ?? {};
	const providerPackage = providerApi.package ?? providerApi.npm ?? record?.provider?.npm;
	return {
		id: String(record?.provider?.id ?? ""),
		models: collectionValues(record?.models).map((model) => normalizeModelSnapshot(model, providerPackage)),
	};
}

function normalizeModelSnapshot(model, providerPackage) {
	const capabilities = model.capabilities ?? {};
	const api = model.api ?? {};
	return {
		id: String(model.id ?? ""),
		name: model.name,
		family: model.family,
		releaseDate: model.releaseDate ?? model.release_date ?? normalizeReleasedTimestamp(model.time?.released) ?? normalizeReleasedTimestamp(model.released),
		status: model.status,
		providerPackage: api.package ?? api.npm ?? providerPackage,
		capabilities: {
			temperature: capabilities.temperature,
			reasoning: capabilities.reasoning,
			attachment: capabilities.attachment,
			tools: capabilities.tools ?? capabilities.toolcall,
			input: normalizeModalities(capabilities.input),
			output: normalizeModalities(capabilities.output),
			interleaved: capabilities.interleaved,
		},
		cost: normalizeCost(model.cost),
		limit: model.limit,
		variants: normalizeVariants(model.variants),
	};
}

function normalizeReleasedTimestamp(value) {
	return typeof value === "number" ? new Date(value).toISOString().slice(0, 10) : undefined;
}

function collectionValues(collection) {
	if (!collection) return [];
	if (typeof collection.values === "function") return Array.from(collection.values());
	if (collection instanceof Map) return Array.from(collection.values());
	if (Array.isArray(collection)) return collection;
	if (typeof collection === "object") return Object.values(collection);
	return [];
}

function litellmCatalogModels(catalog) {
	const records = typeof catalog.provider.list === "function" ? catalog.provider.list() : [];
	const record = records.find((item) => providerRecordID(item) === "litellm");
	return collectionValues(record?.models ?? catalog.provider.get?.("litellm")?.models);
}

function providerRecordID(record) {
	return String(record?.provider?.id ?? record?.id ?? "");
}

function normalizeModalities(value) {
	if (Array.isArray(value)) return value;
	if (!value || typeof value !== "object") return undefined;
	return Object.entries(value)
		.filter(([, enabled]) => enabled)
		.map(([modality]) => modality);
}

function normalizeCost(cost) {
	if (!cost) return undefined;
	if (Array.isArray(cost)) {
		const base = cost[0];
		if (!base) return undefined;
		const contextOver200k = cost.find((tier) => tier?.tier?.type === "context" && tier.tier.size === 200_000);
		const normalized = {
			input: base.input,
			output: base.output,
			cache_read: base.cache?.read,
			cache_write: base.cache?.write,
		};
		if (!contextOver200k) return normalized;
		return {
			...normalized,
			context_over_200k: {
				input: contextOver200k.input,
				output: contextOver200k.output,
				cache_read: contextOver200k.cache?.read,
				cache_write: contextOver200k.cache?.write,
			},
		};
	}
	return cost;
}

function normalizeVariants(variants): Record<string, Record<string, unknown>> | undefined {
	if (!variants) return undefined;
	if (Array.isArray(variants)) return Object.fromEntries(variants.map((variant) => [variant.id, variant.options ?? variant.body ?? {}]));
	return variants;
}

function normalizeBaseUrl(baseUrl: string) {
	const normalized = baseUrl.trim().replace(/\/+$/, "");
	return normalized.endsWith("/v1") ? normalized : `${normalized}/v1`;
}
