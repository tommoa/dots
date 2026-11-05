import {
	discoverLiteLLM,
	resolveOptions,
	warn,
	type LiteLLMOptions,
} from "./discovery";
import { toProvider, type Provider } from "./projection";

export default {
	id: "litellm",
	async setup(ctx) {
		const options = resolveOptions((ctx.options ?? {}) as LiteLLMOptions);
		let provider: Provider | undefined;
		try {
			const catalog = (await ctx.model.list()).data;
			provider = toProvider(await discoverLiteLLM(options), options, catalog);
		} catch (error) {
			warn(
				`Model discovery failed: ${error instanceof Error ? error.message : String(error)}`,
			);
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
			// Discovery and inference share the credential resolved at setup.
			if (options.apiKey) provider.settings.apiKey = options.apiKey;
			provider.settings.headers = { ...options.headers };
			const { models, ...info } = provider;
			await ctx.provider.transform((editor) => {
				editor.add({ info, models });
			});
		}
	},
};
