import { describe, expect, mock, test } from "bun:test";

const { routeLiteLLMResponsesModel, snapshotCatalog, syncCatalogResponsesModelIDs, syncLiteLLMModels, syncResponsesModelIDs } = await import("./plugin-v2");

describe("OpenCode v2 catalog snapshot normalization", () => {
	test("reads release dates from time.released", () => {
		const snapshot = snapshotCatalog({
			provider: {
				list: () => [
					{
						provider: { id: "openai" },
						models: [
							{
								id: "gpt-5.5",
								time: { released: Date.UTC(2025, 11, 4) },
							},
						],
					},
				],
			},
		});

		expect(snapshot.providers[0].models[0].releaseDate).toBe("2025-12-04");
	});

	test("preserves provider-level AI SDK package for models that inherit it", () => {
		const snapshot = snapshotCatalog({
			provider: {
				list: () => [
					{
						provider: { id: "openai", npm: "@ai-sdk/openai" },
						models: [
							{
								id: "gpt-5.5",
								api: { type: "native" },
							},
						],
					},
				],
			},
		});

		expect(snapshot.providers[0].models[0].providerPackage).toBe("@ai-sdk/openai");
	});

	test("preserves context cost tiers from catalog cost arrays", () => {
		const snapshot = snapshotCatalog({
			provider: {
				list: () => [
					{
						provider: { id: "openai" },
						models: [
							{
								id: "gpt-5.5",
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
						],
					},
				],
			},
		});

		expect(snapshot.providers[0].models[0].cost).toEqual({
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
		});
	});
});

describe("OpenCode v2 LiteLLM Responses routing", () => {
	test("tracks only Responses-routed LiteLLM models", () => {
		const responsesModelIDs = new Set(["stale-model"]);

		syncResponsesModelIDs(responsesModelIDs, [
			{
				id: "gpt-5.5",
				api: { package: "@ai-sdk/openai" },
			},
			{
				id: "claude-sonnet-4-5",
				api: { package: "@ai-sdk/openai-compatible" },
			},
		]);

		expect([...responsesModelIDs]).toEqual(["gpt-5.5"]);
	});

	test("rebuilds Responses IDs from existing catalog models after discovery failure", () => {
		const responsesModelIDs = new Set(["stale-model"]);
		const catalog = {
			provider: {
				get: () => ({ id: "litellm" }),
				list: () => [
					{
						provider: { id: "litellm" },
						models: [
							{
								id: "gpt-5.5",
								api: { package: "@ai-sdk/openai" },
							},
							{
								id: "claude-sonnet-4-5",
								api: { package: "@ai-sdk/openai-compatible" },
							},
						],
					},
				],
			},
		};

		syncCatalogResponsesModelIDs(responsesModelIDs, catalog, undefined);

		expect([...responsesModelIDs]).toEqual(["gpt-5.5"]);
	});

	test("routes LiteLLM Responses models through the SDK Responses constructor", () => {
		const event = {
			model: {
				id: "gpt-5.5",
				providerID: "litellm",
				api: { id: "gpt-5.5" },
			},
			sdk: {
				responses: mock((modelID: string) => ({ route: "responses", modelID })),
			},
		};

		routeLiteLLMResponsesModel(event, new Set(["gpt-5.5"]));

		expect(event.sdk.responses).toHaveBeenCalledWith("gpt-5.5");
		expect(event.language).toEqual({ route: "responses", modelID: "gpt-5.5" });
	});

	test("leaves non-LiteLLM or chat-routed models on the default language path", () => {
		for (const event of [
			{
				model: {
					id: "gpt-5.5",
					providerID: "openai",
					api: { id: "gpt-5.5" },
				},
				sdk: { responses: mock(() => ({ route: "responses" })) },
			},
			{
				model: {
					id: "claude-sonnet-4-5",
					providerID: "litellm",
					api: { id: "claude-sonnet-4-5" },
				},
				sdk: { responses: mock(() => ({ route: "responses" })) },
			},
		]) {
			routeLiteLLMResponsesModel(event, new Set(["gpt-5.5"]));

			expect(event.sdk.responses).not.toHaveBeenCalled();
			expect(event.language).toBeUndefined();
		}
	});
});

describe("OpenCode v2 LiteLLM catalog sync", () => {
	test("keeps configured LiteLLM models when discovery fails", () => {
		const remove = mock();
		const update = mock();
		const catalog = {
			provider: {
				get: () => ({
					models: [
						{
							id: "fallback-model",
						},
					],
				}),
			},
			model: {
				remove,
				update,
			},
		};

		syncLiteLLMModels(catalog, undefined);

		expect(remove).not.toHaveBeenCalled();
		expect(update).not.toHaveBeenCalled();
	});

	test("prunes stale LiteLLM models after successful discovery", () => {
		const remove = mock();
		const update = mock((_providerID: string, _modelID: string, apply: (draft: Record<string, unknown>) => void) => {
			apply({ time: {} });
		});
		const catalog = {
			provider: {
				get: () => ({ id: "litellm" }),
				list: () => [
					{
						provider: { id: "litellm" },
						models: [
							{
								id: "stale-model",
							},
							{
								id: "discovered-model",
							},
						],
					},
				],
			},
			model: {
				remove,
				update,
			},
		};

		syncLiteLLMModels(catalog, {
			models: [
				{
					id: "discovered-model",
				},
			],
		});

		expect(remove).toHaveBeenCalledWith("litellm", "stale-model");
		expect(update).toHaveBeenCalledWith("litellm", "discovered-model", expect.any(Function));
	});
});
