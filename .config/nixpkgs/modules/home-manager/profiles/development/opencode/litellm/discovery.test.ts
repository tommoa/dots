import { describe, expect, test } from "bun:test";
import { buildDiscoveryFromEntries, discoverLiteLLM, toV1ProviderConfig, toV2Provider, type CatalogSnapshot, type LiteLLMModelEntry, type LiteLLMOptions } from "./discovery";

const baseOptions: LiteLLMOptions = {
	baseUrl: "https://proxy.example",
	keyFile: "/nonexistent-litellm-key",
};

function providerFor(entries: LiteLLMModelEntry[], options: LiteLLMOptions = {}, catalog?: CatalogSnapshot) {
	return toV2Provider(buildDiscoveryFromEntries(entries, "https://proxy.example/model/info", { ...baseOptions, ...options }, catalog));
}

function v1ProviderFor(entries: LiteLLMModelEntry[], options: LiteLLMOptions = {}, catalog?: CatalogSnapshot) {
	return toV1ProviderConfig(buildDiscoveryFromEntries(entries, "https://proxy.example/model/info", { ...baseOptions, ...options }, catalog));
}

function modelPackage(entry: LiteLLMModelEntry, options?: LiteLLMOptions, catalog?: CatalogSnapshot) {
	return (providerFor([entry], options, catalog).models[0].api as { package: string }).package;
}

function modelVariantIDs(entry: LiteLLMModelEntry, options?: LiteLLMOptions, catalog?: CatalogSnapshot) {
	return providerFor([entry], options, catalog).models[0].variants?.map((variant) => variant.id);
}

function modelVariants(entry: LiteLLMModelEntry, options?: LiteLLMOptions, catalog?: CatalogSnapshot) {
	return providerFor([entry], options, catalog).models[0].variants;
}

function catalog(model: CatalogSnapshot["providers"][number]["models"][number], providerID = "openai"): CatalogSnapshot {
	return {
		providers: [
			{
				id: providerID,
				models: [model],
			},
		],
	};
}

describe("LiteLLM route classification", () => {
	test("responses-style params route through OpenAI Responses even when mode is chat", () => {
		expect(
			modelPackage({
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
					supported_openai_params: ["temperature", "verbosity"],
				},
			}),
		).toBe("@ai-sdk/openai");
	});

	test("chat-compatible params do not route through OpenAI Responses", () => {
		expect(
			modelPackage({
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
					supported_openai_params: ["temperature", "service_tier", "prediction"],
				},
			}),
		).toBe("@ai-sdk/openai-compatible");
	});

	test("uncataloged GPT-5 reasoning_effort routes through OpenAI Responses", () => {
		expect(
			modelPackage({
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
					supported_openai_params: ["reasoning_effort"],
				},
			}),
		).toBe("@ai-sdk/openai");
	});

	test("mode responses routes through OpenAI Responses", () => {
		expect(
			modelPackage({
				model_name: "gpt-5.5",
				model_info: {
					mode: "responses",
				},
			}),
		).toBe("@ai-sdk/openai");
	});

	test("chat override beats all Responses signals", () => {
		expect(
			modelPackage(
				{
					model_name: "gpt-5.5",
					model_info: {
						mode: "responses",
						supported_openai_params: ["verbosity"],
					},
				},
				{ routeOverrides: { chat: ["gpt-5.5"] } },
			),
		).toBe("@ai-sdk/openai-compatible");
	});

	test("responses override beats chat fallback", () => {
		expect(
			modelPackage(
				{
					model_name: "gpt-5.5",
					model_info: {
						mode: "chat",
					},
				},
				{ routeOverrides: { responses: ["gpt-5.5"] } },
			),
		).toBe("@ai-sdk/openai");
	});

	test("reasoning_effort alone does not route Claude or Gemini through Responses", () => {
		for (const model_name of ["claude-sonnet-4-5", "gemini-2.5-pro"]) {
			expect(
				modelPackage({
					model_name,
					model_info: {
						mode: "chat",
						supported_openai_params: ["reasoning_effort"],
					},
				}),
			).toBe("@ai-sdk/openai-compatible");
		}
	});

	test("Claude catalog matches do not switch to Anthropic routing", () => {
		expect(
			modelPackage(
				{
					model_name: "claude-sonnet-4-5",
					litellm_params: { model: "anthropic/claude-sonnet-4-5" },
					model_info: {
						mode: "chat",
					},
				},
				{},
				catalog(
					{
						id: "claude-sonnet-4-5",
						name: "Claude Sonnet 4.5",
						providerPackage: "@ai-sdk/anthropic",
					},
					"anthropic",
				),
			),
		).toBe("@ai-sdk/openai-compatible");
	});
});

describe("LiteLLM generated variants", () => {
	test("dotted GPT Codex versions include xhigh reasoning variants", () => {
		for (const model_name of ["gpt-5.2-codex", "gpt-5.3-codex"]) {
			expect(
				modelVariantIDs({
					model_name,
					model_info: {
						mode: "responses",
						supports_reasoning: true,
					},
				}),
			).toEqual(["low", "medium", "high", "xhigh"]);
		}
	});

	test("matched catalog release dates gate GPT reasoning variants", () => {
		expect(
			modelVariantIDs(
				{
					model_name: "gpt-5.5",
					model_info: {
						supports_reasoning: true,
					},
				},
				{},
				catalog({
					id: "gpt-5.5",
					name: "GPT-5.5",
					releaseDate: "2025-12-04",
					providerPackage: "@ai-sdk/openai",
				}),
			),
		).toEqual(["none", "minimal", "low", "medium", "high", "xhigh"]);
	});

	test("Responses generated variants store runtime settings in the request body", () => {
		const variants = modelVariants({
			model_name: "gpt-5.2-codex",
			model_info: {
				mode: "responses",
				supports_reasoning: true,
			},
		});

		expect(variants?.find((variant) => variant.id === "xhigh")).toEqual({
			id: "xhigh",
			headers: {},
			body: {
				reasoningEffort: "xhigh",
				reasoningSummary: "auto",
				include: ["reasoning.encrypted_content"],
			},
			generation: {},
		});
	});
});

describe("LiteLLM catalog enrichment", () => {
	test("matched catalog variants are reused and LiteLLM limits and costs override catalog values", () => {
		const provider = providerFor(
			[
				{
					model_name: "gpt-5.5",
					model_info: {
						max_input_tokens: 256_000,
						max_output_tokens: 32_000,
						input_cost_per_token: 0.00000125,
						output_cost_per_token: 0.00001,
						supports_reasoning: true,
					},
				},
			],
			{},
			catalog({
				id: "gpt-5.5",
				name: "GPT-5.5",
				providerPackage: "@ai-sdk/openai",
				limit: {
					context: 128_000,
					output: 16_000,
				},
				cost: {
					input: 1,
					output: 2,
				},
				variants: {
					high: {
						reasoningEffort: "high",
						textVerbosity: "medium",
					},
				},
			}),
		);
		const model = provider.models[0];
		expect(model.name).toBe("GPT-5.5");
		expect(model.limit).toEqual({
			context: 256_000,
			input: 256_000,
			output: 32_000,
		});
		expect(model.cost).toEqual([
			{
				input: 1.25,
				output: 10,
				cache: { read: 0, write: 0 },
			},
		]);
		expect(model.variants).toEqual([
			{
				id: "high",
				headers: {},
				body: {
					reasoningEffort: "high",
					textVerbosity: "medium",
				},
				generation: {},
			},
		]);
	});

	test("stale litellm models are absent from the generated provider", () => {
		const provider = providerFor([
			{
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
				},
			},
		]);
		expect(provider.models.map((model) => model.id)).toEqual(["gpt-5.5"]);
	});
});

describe("LiteLLM OpenCode v1 provider config", () => {
	test("injects a config provider that current OpenCode can load", () => {
		const provider = v1ProviderFor([
			{
				model_name: "gpt-5.5",
				model_info: {
					mode: "responses",
					supports_reasoning: true,
				},
			},
			{
				model_name: "claude-sonnet-4-5",
				model_info: {
					mode: "chat",
					supports_function_calling: true,
				},
			},
		]);

		expect(provider).toMatchObject({
			name: "LiteLLM",
			env: ["LITELLM_API_KEY"],
			npm: "@ai-sdk/openai-compatible",
			api: "https://proxy.example/v1",
			options: {
				baseURL: "https://proxy.example/v1",
			},
		});
		expect(provider.models["gpt-5.5"].provider).toEqual({
			npm: "@ai-sdk/openai",
			api: "https://proxy.example/v1",
		});
		expect(provider.models["claude-sonnet-4-5"].provider).toBeUndefined();
	});
});

describe("LiteLLM runtime discovery", () => {
	test("bounds model discovery requests", async () => {
		const originalFetch = globalThis.fetch;
		const originalTimeout = AbortSignal.timeout;
		const timeoutCalls: number[] = [];

		Object.defineProperty(AbortSignal, "timeout", {
			configurable: true,
			value: (milliseconds: number) => {
				timeoutCalls.push(milliseconds);
				const controller = new AbortController();
				queueMicrotask(() => controller.abort());
				return controller.signal;
			},
		});

		globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) =>
			new Promise<Response>((_resolve, reject) => {
				const signal = init?.signal;
				if (!signal) {
					reject(new Error(`Missing signal for ${String(input)}`));
					return;
				}
				signal.addEventListener("abort", () => reject(new DOMException("The operation timed out.", "TimeoutError")), { once: true });
			})) as typeof globalThis.fetch;

		try {
			await expect(
				discoverLiteLLM({
					baseUrl: "https://timeout.example",
					keyFile: "/nonexistent-litellm-key",
				}),
			).rejects.toThrow("GET https://timeout.example/models timed out after 30000ms");
			expect(timeoutCalls).toEqual([30_000, 30_000, 30_000, 30_000]);
		} finally {
			globalThis.fetch = originalFetch;
			Object.defineProperty(AbortSignal, "timeout", {
				configurable: true,
				value: originalTimeout,
			});
		}
	});
});
