import { describe, expect, test } from "bun:test";
import { buildCLIProxyConfig, sanitizedHeaders, transformModels } from "./cli-proxy-api-config";

const entries = [
	{
		model_name: "gpt-response",
		name: "GPT Response",
		model_info: {
			mode: "responses",
			max_input_tokens: 200_000,
			supports_vision: true,
			supports_reasoning: true,
			supports_none_reasoning_effort: true,
			supports_minimal_reasoning_effort: false,
			supports_xhigh_reasoning_effort: true,
			supports_max_reasoning_effort: false,
			supports_ultra_reasoning_effort: true,
		},
	},
	{
		model_name: "claude-chat",
		model_info: { mode: "chat", supports_reasoning: false },
	},
];

describe("transformModels", () => {
	test("projects only CLIProxyAPI model metadata", () => {
		expect(transformModels(entries)).toEqual([
			{
				id: "claude-chat",
				displayName: "claude-chat",
				route: "chat",
				contextLength: undefined,
				inputModalities: ["text"],
				reasoningEfforts: [],
			},
			{
				id: "gpt-response",
				displayName: "GPT Response",
				route: "responses",
				contextLength: 200_000,
				inputModalities: ["text", "image"],
				reasoningEfforts: ["none", "low", "medium", "high", "xhigh", "ultra"],
			},
		]);
	});

	test("filters embeddings, deduplicates IDs, and honors route overrides", () => {
		expect(
			transformModels(
				[
					...entries,
					entries[0],
					{ model_name: "text-embedding-3", model_info: { mode: "embedding" } },
				],
				{ routeOverrides: { chat: ["gpt-response"] } },
			).map(({ id, route }) => ({ id, route })),
		).toEqual([
			{ id: "claude-chat", route: "chat" },
			{ id: "gpt-response", route: "chat" },
		]);
	});
});

describe("buildCLIProxyConfig", () => {
	test("publishes namespaced Responses and Chat providers", () => {
		const config = buildCLIProxyConfig(
			{ host: "127.0.0.1", "openai-compatibility": [{ name: "existing" }] },
			transformModels(entries),
			"secret",
			"https://ai-proxy.example/v1",
		);

		expect(config["force-model-prefix"]).toBe(true);
		expect(config["codex-api-key"]).toEqual([
			{
				"api-key": "secret",
				prefix: "ai-proxy",
				"base-url": "https://ai-proxy.example/v1",
				models: [
					{
						name: "gpt-response",
						alias: "gpt-response",
						"display-name": "GPT Response (ai-proxy)",
						"max-context-length": 200_000,
						"input-modalities": ["text", "image"],
						thinking: { levels: ["none", "low", "medium", "high", "xhigh", "ultra"] },
					},
				],
			},
		]);
		expect(config["openai-compatibility"]).toHaveLength(2);
		expect((config["openai-compatibility"] as Array<{ models?: unknown[] }>)[1].models).toEqual([
			{
				name: "claude-chat",
				alias: "claude-chat",
				"display-name": "claude-chat (ai-proxy)",
				"input-modalities": ["text"],
				thinking: { levels: [] },
			},
		]);
	});

	test("does not mutate the declarative base", () => {
		const base = { routing: { strategy: "fill-first" } };
		buildCLIProxyConfig(base, transformModels(entries), "secret", "https://ai-proxy.example/v1");
		expect(base).toEqual({ routing: { strategy: "fill-first" } });
	});
});

describe("sanitizedHeaders", () => {
	test("passes non-secret headers through unchanged", () => {
		expect(sanitizedHeaders({ "X-Tenant": "acme" })).toEqual({ "X-Tenant": "acme" });
	});

	test("rejects Authorization entries regardless of casing", () => {
		expect(() => sanitizedHeaders({ authorization: "Bearer x" })).toThrow(/Authorization/);
		expect(() => sanitizedHeaders({ AUTHORIZATION: "Bearer x" })).toThrow(/Authorization/);
	});
});
