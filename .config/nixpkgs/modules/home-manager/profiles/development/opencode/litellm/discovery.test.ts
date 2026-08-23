import { describe, expect, test } from "bun:test";
import {
	buildDiscoveryFromEntries,
	discoverLiteLLM,
	normalizeOptions,
	type CatalogModelSnapshot,
	type CatalogSnapshot,
	type LiteLLMModelEntry,
	type LiteLLMOptions,
} from "./discovery";
import { toV1ProviderConfig } from "./projection-v1";
import { toV2Provider } from "./projection-v2";

const baseOptions: LiteLLMOptions = {
	baseUrl: "https://proxy.example",
	keyFile: "/nonexistent-litellm-key",
};

function providerFor(
	entries: LiteLLMModelEntry[],
	options: LiteLLMOptions = {},
	catalog?: CatalogSnapshot,
) {
	return toV2Provider(discoveryFor(entries, options, catalog));
}

function v1ProviderFor(
	entries: LiteLLMModelEntry[],
	options: LiteLLMOptions = {},
	catalog?: CatalogSnapshot,
) {
	return toV1ProviderConfig(discoveryFor(entries, options, catalog));
}

function discoveryFor(
	entries: LiteLLMModelEntry[],
	options: LiteLLMOptions = {},
	catalog?: CatalogSnapshot,
) {
	return buildDiscoveryFromEntries(
		entries,
		"https://proxy.example/model/info",
		normalizeOptions({ ...baseOptions, ...options }),
		catalog,
	);
}

function modelPackage(
	entry: LiteLLMModelEntry,
	options?: LiteLLMOptions,
	catalog?: CatalogSnapshot,
) {
	return providerFor([entry], options, catalog).models[0].package;
}

function modelVariantIDs(
	entry: LiteLLMModelEntry,
	options?: LiteLLMOptions,
	catalog?: CatalogSnapshot,
) {
	return providerFor([entry], options, catalog).models[0].variants?.map(
		(variant) => variant.id,
	);
}

function modelVariants(
	entry: LiteLLMModelEntry,
	options?: LiteLLMOptions,
	catalog?: CatalogSnapshot,
) {
	return providerFor([entry], options, catalog).models[0].variants;
}

function catalog(model: CatalogModelSnapshot): CatalogSnapshot {
	return new Map([[model.id, model]]);
}

describe("LiteLLM route projection", () => {
	test("chat-compatible params do not route through OpenAI Responses", () => {
		expect(
			modelPackage({
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
					supported_openai_params: [
						"temperature",
						"service_tier",
						"prediction",
					],
				},
			}),
		).toBe("@opencode-ai/ai/providers/openai-compatible");
	});

	test("mode responses routes through OpenAI Responses", () => {
		expect(
			modelPackage({
				model_name: "gpt-5.5",
				model_info: {
					mode: "responses",
				},
			}),
		).toBe("@opencode-ai/ai/providers/openai/responses");
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

	test("Responses generated variants store runtime options in settings", () => {
		const variants = modelVariants({
			model_name: "gpt-5.2-codex",
			model_info: {
				mode: "responses",
				supports_reasoning: true,
			},
		});

		expect(variants?.find((variant) => variant.id === "xhigh")).toEqual({
			id: "xhigh",
			settings: {
				reasoningEffort: "xhigh",
				reasoningSummary: "auto",
				include: ["reasoning.encrypted_content"],
			},
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
				settings: {
					reasoningEffort: "high",
					textVerbosity: "medium",
				},
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
	test("keeps catalog provenance internal to discovery", () => {
		const snapshot = catalog({
			id: "gpt-5.5",
			name: "GPT-5.5",
			providerPackage: "@ai-sdk/openai",
		});
		const entry = {
			model_name: "work-gpt",
			litellm_params: { model: "openai/gpt-5.5" },
			model_info: { mode: "responses" },
		};

		expect(discoveryFor([entry], {}, snapshot).models[0].catalogModelID).toBe(
			"gpt-5.5",
		);
		expect(
			v1ProviderFor([entry], {}, snapshot).models["work-gpt"],
		).not.toHaveProperty("catalogModelID");
	});

	test("injects a provider that OpenCode v1 can load", () => {
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
			options: { baseURL: "https://proxy.example/v1" },
		});
		expect(provider.models["gpt-5.5"].provider).toEqual({
			npm: "@ai-sdk/openai",
			api: "https://proxy.example/v1",
		});
		expect(provider.models["claude-sonnet-4-5"].provider).toBeUndefined();
	});

	test("fills missing price fields required by the v1 config schema", () => {
		const provider = v1ProviderFor([
			{
				model_name: "gpt-5.6-luna",
				model_info: {
					mode: "responses",
					output_cost_per_token: 0.00001,
				},
			},
		]);

		expect(provider.models["gpt-5.6-luna"].cost).toEqual({
			input: 0,
			output: 10,
			cache_read: 0,
			cache_write: 0,
		});
	});

	test("parses numeric price strings returned by LiteLLM", () => {
		const provider = v1ProviderFor([
			{
				model_name: "gpt-5.6-luna",
				model_info: {
					mode: "responses",
					input_cost_per_token: "2e-07",
					output_cost_per_token: 0.0000012,
					cache_read_input_token_cost: "2e-08",
					cache_creation_input_token_cost: 2.5e-7,
				},
			},
		]);

		expect(provider.models["gpt-5.6-luna"].cost).toEqual({
			input: 0.2,
			output: 1.2,
			cache_read: 0.02,
			cache_write: 0.25,
		});
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
				signal.addEventListener(
					"abort",
					() =>
						reject(
							new DOMException("The operation timed out.", "TimeoutError"),
						),
					{ once: true },
				);
			})) as typeof globalThis.fetch;

		try {
			await expect(
				discoverLiteLLM(
					normalizeOptions({
						baseUrl: "https://timeout.example",
						keyFile: "/nonexistent-litellm-key",
					}),
				),
			).rejects.toThrow(
				"GET https://timeout.example/models timed out after 30000ms",
			);
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
