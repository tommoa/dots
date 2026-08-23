import type { DiscoveredLiteLLM, DiscoveredModel } from "./discovery";

export interface V1ProviderConfig {
	name: string;
	env: string[];
	npm: string;
	api: string;
	options: Record<string, unknown>;
	models: Record<string, Record<string, unknown>>;
}

export function toV1ProviderConfig(
	discovery: DiscoveredLiteLLM,
): V1ProviderConfig {
	return {
		name: discovery.providerName,
		env: [discovery.apiKeyEnv],
		npm: "@ai-sdk/openai-compatible",
		api: discovery.baseUrl,
		options: { baseURL: discovery.baseUrl },
		models: Object.fromEntries(
			discovery.models.map((model) => [
				model.id,
				toV1Model(model, discovery.baseUrl),
			]),
		),
	};
}

export function mergeV1ProviderConfig(
	discovered: V1ProviderConfig,
	configured?: Partial<V1ProviderConfig>,
) {
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

function toV1Model(model: DiscoveredModel, baseUrl: string) {
	const result: Record<string, unknown> = {
		id: model.id,
		name: model.name,
		temperature: model.capabilities.temperature ?? false,
		reasoning: model.capabilities.reasoning ?? false,
		attachment: model.capabilities.attachment ?? false,
		tool_call: model.capabilities.tools ?? false,
		modalities: {
			input: model.capabilities.input,
			output: model.capabilities.output,
		},
		cost: model.cost,
		limit: model.limit,
		variants: model.variants,
		status: model.status ?? "active",
	};
	if (model.family) result.family = model.family;
	if (model.releaseDate) result.release_date = model.releaseDate;
	if (model.capabilities.interleaved)
		result.interleaved = model.capabilities.interleaved;
	if (model.route === "responses") {
		result.provider = {
			npm: "@ai-sdk/openai",
			api: baseUrl,
		};
	}
	return result;
}
