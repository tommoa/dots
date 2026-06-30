import { describe, expect, test } from "bun:test";
import { classifyLiteLLMRoute, type LiteLLMModelEntry } from "./routing";

function route(entry: LiteLLMModelEntry, options?: Parameters<typeof classifyLiteLLMRoute>[1]) {
	return classifyLiteLLMRoute(entry, options);
}

describe("LiteLLM route classification", () => {
	test("responses-style params route through OpenAI Responses even when mode is chat", () => {
		expect(
			route({
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
					supported_openai_params: ["temperature", "verbosity"],
				},
			}),
		).toBe("responses");
	});

	test("chat-compatible params do not route through OpenAI Responses", () => {
		expect(
			route({
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
					supported_openai_params: ["temperature", "service_tier", "prediction"],
				},
			}),
		).toBe("chat");
	});

	test("uncataloged GPT-5 reasoning_effort routes through OpenAI Responses", () => {
		expect(
			route({
				model_name: "gpt-5.5",
				model_info: {
					mode: "chat",
					supported_openai_params: ["reasoning_effort"],
				},
			}),
		).toBe("responses");
	});

	test("mode responses routes through OpenAI Responses", () => {
		expect(
			route({
				model_name: "gpt-5.5",
				model_info: {
					mode: "responses",
				},
			}),
		).toBe("responses");
	});

	test("OpenAI Responses catalog and API matches route through OpenAI Responses", () => {
		const entry = {
			model_name: "gpt-5.5",
			model_info: {
				mode: "chat",
			},
		};

		expect(route(entry, { match: { providerPackage: "@ai-sdk/openai" } })).toBe("responses");
		expect(route(entry, { match: { api: "openai-responses" } })).toBe("responses");
	});

	test("chat override beats all Responses signals", () => {
		expect(
			route(
				{
					model_name: "gpt-5.5",
					model_info: {
						mode: "responses",
						supported_openai_params: ["verbosity"],
					},
				},
				{ routeOverrides: { chat: ["gpt-5.5"] } },
			),
		).toBe("chat");
	});

	test("responses override beats chat fallback", () => {
		expect(
			route(
				{
					model_name: "gpt-5.5",
					model_info: {
						mode: "chat",
					},
				},
				{ routeOverrides: { responses: ["gpt-5.5"] } },
			),
		).toBe("responses");
	});

	test("reasoning_effort alone does not route Claude or Gemini through Responses", () => {
		for (const model_name of ["claude-sonnet-4-5", "gemini-2.5-pro"]) {
			expect(
				route({
					model_name,
					model_info: {
						mode: "chat",
						supported_openai_params: ["reasoning_effort"],
					},
				}),
			).toBe("chat");
		}
	});
});
