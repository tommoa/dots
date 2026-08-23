import {
	discoverLiteLLM,
	normalizeOptions,
	warn,
	type LiteLLMOptions,
	type NormalizedLiteLLMOptions,
} from "./discovery";
import {
	mergeV1ProviderConfig,
	toV1ProviderConfig,
	type V1ProviderConfig,
} from "./projection-v1";
import {
	snapshotV2Catalog,
	syncLiteLLMCatalog,
	toV2Provider,
	type V2CatalogDraft,
	type V2CatalogReader,
	type V2Provider,
} from "./projection-v2";

export default {
	id: "litellm",
	server(_input, rawOptions) {
		const options = normalizeOptions((rawOptions ?? {}) as LiteLLMOptions);
		return {
			async config(config) {
				try {
					const provider = toV1ProviderConfig(await discoverLiteLLM(options));
					config.provider ??= {};
					config.provider.litellm = mergeV1ProviderConfig(
						provider,
						config.provider.litellm as Partial<V1ProviderConfig> | undefined,
					);
				} catch (error) {
					warn(`Model discovery failed: ${errorMessage(error)}`);
				}
			},
		};
	},
	async setup(ctx) {
		const options = normalizeOptions((ctx.options ?? {}) as LiteLLMOptions);
		let provider: V2Provider | undefined;
		try {
			provider = await loadV2Provider(ctx.catalog, options);
		} catch (error) {
			warn(`Model discovery failed: ${errorMessage(error)}`);
		}

		await ctx.integration.transform((draft) => {
			draft.update("litellm", (integration) => {
				integration.name = options.providerName;
			});
			draft.method.update({
				integrationID: "litellm",
				method: { type: "env", names: [options.apiKeyEnv] },
			});
			draft.method.update({
				integrationID: "litellm",
				method: { type: "key", label: "LiteLLM API key" },
			});
		});

		if (provider) {
			await ctx.catalog.transform((catalog: V2CatalogDraft) => {
				syncLiteLLMCatalog(catalog, provider);
			});
		}
	},
};

async function loadV2Provider(
	catalog: V2CatalogReader,
	options: NormalizedLiteLLMOptions,
): Promise<V2Provider> {
	const snapshot = await snapshotV2Catalog(catalog);
	return toV2Provider(
		await discoverLiteLLM(options, snapshot.discovery),
		snapshot,
	);
}

function errorMessage(error: unknown) {
	return error instanceof Error ? error.message : String(error);
}
