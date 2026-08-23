import { describe, expect, mock, test } from "bun:test";
import {
	buildDiscoveryFromEntries,
	type LiteLLMModelEntry,
	normalizeOptions,
} from "./discovery";
import type { V2Model, V2Provider } from "./projection-v2";

const { default: plugin } = await import("./plugin");
const { catalogSnapshotFromV2, syncLiteLLMCatalog, toV2Provider } =
	await import("./projection-v2");

function catalogHarness(models: Record<string, unknown>[] = []) {
	const providerDraft: Record<string, unknown> = {};
	const modelDrafts = new Map<string, Record<string, unknown>>(
		models
			.filter((model) => model.providerID === "litellm")
			.map((model) => [String(model.id), model]),
	);
	const draft = {
		provider: {
			list: () =>
				Object.keys(providerDraft).length > 0 || modelDrafts.size > 0
					? [
							{
								provider:
									Object.keys(providerDraft).length > 0
										? providerDraft
										: { id: "litellm" },
								models: modelDrafts,
							},
						]
					: [],
			update: (
				providerID: string,
				update: (item: Record<string, unknown>) => void,
			) => {
				providerDraft.id ??= providerID;
				providerDraft.name ??= providerID;
				providerDraft.package ??= "";
				update(providerDraft);
			},
		},
		model: {
			remove: (_providerID: string, modelID: string) =>
				modelDrafts.delete(modelID),
			update: (
				_providerID: string,
				modelID: string,
				update: (item: Record<string, unknown>) => void,
			) => {
				const item = modelDrafts.get(modelID) ?? {
					id: modelID,
					modelID,
					providerID: "litellm",
					name: modelID,
					capabilities: {
						tools: true,
						input: ["text", "image"],
						output: ["text"],
					},
					variants: [],
					time: { released: 0 },
					cost: [],
					status: "active",
					enabled: true,
					limit: { context: 0, output: 0 },
				};
				update(item);
				modelDrafts.set(modelID, item);
			},
		},
	};
	const transform = mock((apply: (catalog: typeof draft) => void) => {
		expect(apply(draft)).toBeUndefined();
	});
	return {
		catalog: {
			model: { list: async () => ({ data: models, location: {} }) },
			transform,
		},
		draft,
		modelDrafts,
		providerDraft,
	};
}

function discoveredProvider(models: V2Model[] = []): V2Provider {
	return {
		id: "litellm",
		name: "LiteLLM",
		integrationID: "litellm",
		package: "@opencode-ai/ai/providers/openai-compatible",
		settings: { baseURL: "https://proxy.example/v1", provider: "litellm" },
		models,
	};
}

function catalogModel(id: string, providerID = "openai") {
	return {
		id,
		modelID: id,
		providerID,
		name: id,
		package: "@opencode-ai/ai/providers/openai",
		settings: {},
		capabilities: { tools: true, input: ["text"], output: ["text"] },
		variants: [],
		time: { released: 0 },
		cost: [],
		status: "active" as const,
		enabled: true,
		limit: { context: 200_000, output: 32_000 },
	};
}

function discoveredModel(overrides: Partial<V2Model> = {}): V2Model {
	return {
		id: "gpt-5.5",
		modelID: "gpt-5.5",
		providerID: "litellm",
		name: "GPT-5.5",
		package: "@opencode-ai/ai/providers/openai/responses",
		settings: { baseURL: "https://proxy.example/v1", provider: "litellm" },
		capabilities: { tools: true, input: ["text"], output: ["text"] },
		cost: [],
		limit: { context: 128_000, output: 16_384 },
		variants: [],
		time: { released: 2 },
		status: "active",
		enabled: true,
		family: undefined,
		...overrides,
	};
}

function projectCatalogModels(
	entries: LiteLLMModelEntry[],
	models: Parameters<typeof catalogSnapshotFromV2>[0],
) {
	const snapshot = catalogSnapshotFromV2(models);
	const discovery = buildDiscoveryFromEntries(
		entries,
		"https://proxy.example/model/info",
		normalizeOptions({
			baseUrl: "https://proxy.example",
			keyFile: "/nonexistent-litellm-key",
		}),
		snapshot.discovery,
	);
	return { discovery, provider: toV2Provider(discovery, snapshot) };
}

describe("OpenCode v2 LiteLLM catalog sync", () => {
	test("replays complete definitions and prunes stale LiteLLM models", () => {
		const previous = {
			...catalogModel("gpt-5.5", "litellm"),
			package: "old-package",
			settings: { existing: "discard" },
			time: { released: 1 },
		};
		const harness = catalogHarness([
			previous,
			catalogModel("stale-model", "litellm"),
		]);
		const model = discoveredModel();

		syncLiteLLMCatalog(harness.draft, discoveredProvider([model]));

		expect(harness.modelDrafts.has("stale-model")).toBeFalse();
		expect(harness.modelDrafts.get("gpt-5.5")).toEqual(model);
		expect(harness.providerDraft).toEqual({
			id: "litellm",
			name: "LiteLLM",
			integrationID: "litellm",
			package: "@opencode-ai/ai/providers/openai-compatible",
			settings: { baseURL: "https://proxy.example/v1", provider: "litellm" },
		});
	});

	test("normalizes the public V2 catalog for discovery enrichment", () => {
		const snapshot = catalogSnapshotFromV2([
			{
				...catalogModel("gpt-5.5"),
				family: "gpt-5",
				capabilities: {
					tools: true,
					input: ["text", "image"],
					output: ["text"],
				},
				variants: [{ id: "high", body: { reasoningEffort: "high" } }],
				time: { released: Date.UTC(2025, 11, 4) },
				cost: [
					{ input: 1.25, output: 10, cache: { read: 0.125, write: 1.25 } },
					{
						tier: { type: "context", size: 200_000 },
						input: 2.5,
						output: 20,
						cache: { read: 0.25, write: 2.5 },
					},
				],
			},
		]);

		expect(snapshot.discovery).toEqual(
			new Map([
				[
					"gpt-5.5",
					{
						id: "gpt-5.5",
						name: "gpt-5.5",
						family: "gpt-5",
						releaseDate: "2025-12-04",
						status: "active",
						providerPackage: "@opencode-ai/ai/providers/openai",
						capabilities: {
							tools: true,
							attachment: true,
							input: ["text", "image"],
							output: ["text"],
						},
						cost: {
							input: 1.25,
							output: 10,
							cache_read: 0.125,
							cache_write: 1.25,
							context_over_200k: {
								input: 2.5,
								output: 20,
								cache_read: 0.25,
								cache_write: 2.5,
							},
						},
						limit: { context: 200_000, output: 32_000 },
						variants: { high: { reasoningEffort: "high" } },
					},
				],
			]),
		);
		expect(snapshot.metadata.get("gpt-5.5")).toEqual({
			variants: [{ id: "high", body: { reasoningEffort: "high" } }],
			compatibility: undefined,
			cost: [
				{ input: 1.25, output: 10, cache: { read: 0.125, write: 1.25 } },
				{
					tier: { type: "context", size: 200_000 },
					input: 2.5,
					output: 20,
					cache: { read: 0.25, write: 2.5 },
				},
			],
		});
	});

	test("preserves native metadata for alias and canonical catalog matches", () => {
		const variants = [
			{
				id: "high",
				settings: { reasoningEffort: "high" },
				headers: { "x-reasoning-mode": "high" },
				body: { service_tier: "priority" },
			},
		];
		const compatibility = {
			reasoningField: "reasoning_details",
			maxTokensField: "max_completion_tokens" as const,
			requireFinishReason: true,
		};
		const cost = [
			{ input: 1, output: 2, cache: { read: 0.1, write: 0.2 } },
			{
				tier: { type: "context" as const, size: 128_000 },
				input: 1.5,
				output: 3,
				cache: { read: 0.15, write: 0.3 },
			},
			{
				tier: { type: "context" as const, size: 500_000 },
				input: 4,
				output: 8,
				cache: { read: 0.4, write: 0.8 },
			},
		];
		const { discovery, provider } = projectCatalogModels(
			[
				{
					model_name: "work-gpt",
					litellm_params: { model: "openai/gpt-5.5" },
					model_info: { mode: "chat" },
				},
				{
					model_name: "gpt-5.5-20251204",
					model_info: { mode: "chat" },
				},
			],
			[
				{
					...catalogModel("gpt-5.5", "anthropic"),
					name: "Lower-priority GPT-5.5",
					variants: [{ id: "low", settings: { reasoningEffort: "low" } }],
					compatibility: { reasoningField: "reasoning_content" },
					cost: [{ input: 100, output: 200, cache: { read: 10, write: 20 } }],
				},
				{
					...catalogModel("gpt-5.5"),
					variants,
					compatibility,
					cost,
				},
			],
		);

		expect(discovery.models.map((model) => model.catalogModelID)).toEqual([
			"gpt-5.5",
			"gpt-5.5",
		]);
		for (const model of provider.models) {
			expect(model.variants).toEqual(variants);
			expect(model.compatibility).toEqual(compatibility);
			expect(model.cost).toEqual(cost);
		}
	});

	test("merges effective costs by tier identity without dropping other tiers", () => {
		const base = { input: 1, output: 2, cache: { read: 0.1, write: 0.2 } };
		const context128k = {
			tier: { type: "context" as const, size: 128_000 },
			input: 1.5,
			output: 3,
			cache: { read: 0.15, write: 0.3 },
		};
		const context200k = {
			tier: { type: "context" as const, size: 200_000 },
			input: 2,
			output: 4,
			cache: { read: 0.2, write: 0.4 },
		};
		const context500k = {
			tier: { type: "context" as const, size: 500_000 },
			input: 4,
			output: 8,
			cache: { read: 0.4, write: 0.8 },
		};
		const snapshot = catalogSnapshotFromV2([
			{
				...catalogModel("gpt-5.5"),
				cost: [base, context128k, context200k, context500k],
			},
		]);
		const discovery = buildDiscoveryFromEntries(
			[{ model_name: "gpt-5.5", model_info: { mode: "chat" } }],
			"https://proxy.example/model/info",
			normalizeOptions({ baseUrl: "https://proxy.example" }),
			snapshot.discovery,
		);
		discovery.models[0].cost = {
			input: 10,
			output: 20,
			cache_read: 1,
			cache_write: 2,
			context_over_200k: {
				input: 30,
				output: 40,
				cache_read: 3,
				cache_write: 4,
			},
		};

		expect(toV2Provider(discovery, snapshot).models[0].cost).toEqual([
			{ input: 10, output: 20, cache: { read: 1, write: 2 } },
			context128k,
			{
				tier: { type: "context", size: 200_000 },
				input: 30,
				output: 40,
				cache: { read: 3, write: 4 },
			},
			context500k,
		]);
	});
});

describe("LiteLLM plugin definitions", () => {
	test("enriches discovery before synchronously applying the V2 catalog transform", async () => {
		const originalFetch = globalThis.fetch;
		const models = [
			{
				...catalogModel("gpt-5.5"),
				name: "GPT-5.5",
				capabilities: {
					tools: true,
					input: ["text", "image"],
					output: ["text"],
				},
				compatibility: {
					reasoningField: "reasoning_details",
					maxTokensField: "max_completion_tokens",
					requireFinishReason: true,
				},
				variants: [
					{
						id: "high",
						settings: { reasoningEffort: "high" },
						headers: { "x-reasoning-mode": "high" },
						body: { service_tier: "priority" },
					},
				],
				cost: [
					{ input: 99, output: 99, cache: { read: 9, write: 9 } },
					{
						tier: { type: "context", size: 128_000 },
						input: 1.5,
						output: 12,
						cache: { read: 0.15, write: 1.5 },
					},
					{
						tier: { type: "context", size: 500_000 },
						input: 4,
						output: 32,
						cache: { read: 0.4, write: 4 },
					},
				],
			},
		];
		const harness = catalogHarness(models);
		globalThis.fetch = (() =>
			Promise.resolve(
				Response.json({
					data: [
						{
							model_name: "gpt-5.5",
							model_info: {
								mode: "chat",
								input_cost_per_token: 0.00000125,
								output_cost_per_token: 0.00001,
								cache_read_input_token_cost: 1.25e-7,
								cache_creation_input_token_cost: 0.00000125,
							},
						},
					],
				}),
			)) as typeof globalThis.fetch;

		try {
			await plugin.setup({
				options: {
					baseUrl: "https://proxy.example",
					keyFile: "/nonexistent-litellm-key",
				},
				integration: { transform: mock() },
				catalog: harness.catalog,
			});
		} finally {
			globalThis.fetch = originalFetch;
		}

		expect(harness.providerDraft).toMatchObject({
			package: "@opencode-ai/ai/providers/openai-compatible",
			settings: { baseURL: "https://proxy.example/v1", provider: "litellm" },
		});
		expect(harness.modelDrafts.get("gpt-5.5")).toMatchObject({
			name: "GPT-5.5",
			package: "@opencode-ai/ai/providers/openai/responses",
			capabilities: { tools: true, input: ["text", "image"], output: ["text"] },
			limit: { context: 200_000, output: 32_000 },
			compatibility: {
				reasoningField: "reasoning_details",
				maxTokensField: "max_completion_tokens",
				requireFinishReason: true,
			},
			cost: [
				{
					input: 1.25,
					output: 10,
					cache: { read: 0.125, write: 1.25 },
				},
				{
					tier: { type: "context", size: 128_000 },
					input: 1.5,
					output: 12,
					cache: { read: 0.15, write: 1.5 },
				},
				{
					tier: { type: "context", size: 500_000 },
					input: 4,
					output: 32,
					cache: { read: 0.4, write: 4 },
				},
			],
			variants: [
				{
					id: "high",
					settings: { reasoningEffort: "high" },
					headers: { "x-reasoning-mode": "high" },
					body: { service_tier: "priority" },
				},
			],
		});
	});

	test("keeps integration metadata but leaves the catalog empty when startup discovery fails", async () => {
		const originalFetch = globalThis.fetch;
		const originalWarn = console.warn;
		const harness = catalogHarness();
		const integrationDraft: Record<string, unknown> = {};
		const methods: Record<string, unknown>[] = [];
		const integration = {
			transform: mock((apply) =>
				apply({
					update: (
						_id: string,
						update: (draft: Record<string, unknown>) => void,
					) => update(integrationDraft),
					method: {
						update: (method: Record<string, unknown>) => methods.push(method),
					},
				}),
			),
		};
		globalThis.fetch = (() =>
			Promise.resolve(
				new Response("unavailable", { status: 503 }),
			)) as typeof globalThis.fetch;
		const warnMock = mock();
		console.warn = warnMock;

		try {
			await plugin.setup({
				options: {
					baseUrl: "https://proxy.example",
					apiKeyEnv: " ",
					keyFile: "/nonexistent-litellm-key",
				},
				integration,
				catalog: harness.catalog,
			});
		} finally {
			globalThis.fetch = originalFetch;
			console.warn = originalWarn;
		}

		expect(integrationDraft).toEqual({ name: "LiteLLM" });
		expect(methods).toEqual([
			{
				integrationID: "litellm",
				method: { type: "env", names: ["LITELLM_API_KEY"] },
			},
			{
				integrationID: "litellm",
				method: { type: "key", label: "LiteLLM API key" },
			},
		]);
		expect(harness.providerDraft).toEqual({});
		expect(harness.modelDrafts.size).toBe(0);
		expect(harness.catalog.transform).not.toHaveBeenCalled();
		expect(warnMock).toHaveBeenCalledTimes(1);
	});

	test("loads through the V1 server entry and preserves configured overrides", async () => {
		const originalFetch = globalThis.fetch;
		globalThis.fetch = (() =>
			Promise.resolve(
				Response.json({
					data: [{ model_name: "gpt-5.5", model_info: { mode: "responses" } }],
				}),
			)) as typeof globalThis.fetch;
		const config = {
			provider: {
				litellm: {
					name: "Configured LiteLLM",
					options: { timeout: 30_000 },
					models: { "configured-model": { name: "Configured model" } },
				},
			},
		};

		try {
			const hooks = plugin.server(
				{},
				{
					baseUrl: "https://proxy.example",
					apiKeyEnv: " ",
					keyFile: "/nonexistent-litellm-key",
				},
			);
			await hooks.config(config);
		} finally {
			globalThis.fetch = originalFetch;
		}

		expect(config.provider.litellm).toMatchObject({
			name: "Configured LiteLLM",
			env: ["LITELLM_API_KEY"],
			npm: "@ai-sdk/openai-compatible",
			api: "https://proxy.example/v1",
			options: { baseURL: "https://proxy.example/v1", timeout: 30_000 },
			models: {
				"gpt-5.5": {
					provider: { npm: "@ai-sdk/openai", api: "https://proxy.example/v1" },
				},
				"configured-model": { name: "Configured model" },
			},
		});
	});

	test("exposes both OpenCode plugin entry points", () => {
		expect(typeof plugin.id).toBe("string");
		expect(typeof plugin.setup).toBe("function");
		expect(typeof plugin.server).toBe("function");
	});
});
