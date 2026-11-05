import {
	discoverLiteLLM,
	normalizeOptions,
	warn,
	type LiteLLMOptions,
} from "./discovery";
import {
	catalogSnapshotFromModels,
	toProvider,
	type Provider,
} from "./projection";

export default {
	id: "litellm",
	async setup(ctx) {
		const options = normalizeOptions((ctx.options ?? {}) as LiteLLMOptions);
		let provider: Provider | undefined;
		try {
			const snapshot = catalogSnapshotFromModels((await ctx.model.list()).data);
			provider = toProvider(
				await discoverLiteLLM(options, snapshot.discovery),
				snapshot,
			);
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
			if (options.apiKey) provider.settings.apiKey = options.apiKey;
			provider.settings.headers = { ...options.headers };
			const { models, ...info } = provider;
			await ctx.provider.transform((editor) => {
				editor.add({ info, models });
			});
		}
	},
};

function errorMessage(error: unknown) {
	return error instanceof Error ? error.message : String(error);
}
