import { proxyModelRoute, type ProxyModel } from "../../ai-providers/routing";
import { toReasoningVariants, type ModelMetadata } from "../models";

const providerID = "cli_proxy_api";
const responsesPackage = "@opencode/ai/providers/openai/responses";
const chatPackage = "@opencode/ai/providers/openai-compatible";

interface Model extends ModelMetadata {
	modelID: string;
	providerID: string;
	type?: string;
	settings?: Record<string, unknown>;
	body?: Record<string, unknown>;
}

export function projectProxyModels(
	entries: ProxyModel[],
	catalog: Model[],
): Model[] {
	const native = catalog.filter((model) => model.providerID === "openai");
	const result = new Map<string, Model>();
	for (const entry of entries) {
		const isCorporate = entry.id.startsWith("ai-proxy/");
		const upstreamID = isCorporate
			? entry.id.slice("ai-proxy/".length)
			: entry.id;
		// These use image/embedding endpoints, not the agent's chat protocol.
		if (/^gpt-image-|embedding/i.test(upstreamID)) continue;
		const source = isCorporate
			? catalog.find((model) => model.id === upstreamID)
			: native.find((model) => model.id === upstreamID);
		const route = proxyModelRoute(entry);
		const model: Model = {
			id: entry.id,
			modelID: entry.id,
			providerID,
			type: "chat",
			name: entry.display_name || entry.id,
			package: route === "responses" ? responsesPackage : chatPackage,
			// Do not copy native settings/headers: they contain the direct endpoint
			// and account identity, which must remain owned by CLIProxyAPI.
			settings: {},
			...(source?.family ? { family: source.family } : {}),
			...(source?.compatibility
				? { compatibility: structuredClone(source.compatibility) }
				: {}),
			capabilities: {
				...source?.capabilities,
				tools: true,
				input: [
					...(entry.supportedInputModalities ?? source?.capabilities.input ?? ["text"]),
				],
				output: [
					...(entry.supportedOutputModalities ?? source?.capabilities.output ?? ["text"]),
				],
			},
			variants: toReasoningVariants(entry.thinking?.levels ?? [], route),
			time: source?.time ?? { released: 0 },
			cost: isCorporate ? structuredClone(source?.cost ?? []) : [],
			status: source?.status ?? "active",
			enabled: true,
			limit: {
				context:
					entry.max_context_length ??
					entry.context_length ??
					source?.limit.context ??
					128_000,
				output: entry.max_completion_tokens ?? source?.limit.output ?? 16_384,
			},
		};
		result.set(model.id, model);
		if (isCorporate) continue;
		for (const speed of native.filter(
			(candidate) =>
				candidate.modelID === upstreamID &&
				["priority", "ultrafast"].includes(
					String(candidate.body?.service_tier),
				),
		)) {
			result.set(speed.id, {
				...structuredClone(model),
				id: speed.id,
				name: speed.name,
				// The speed suffix is a local choice, never a proxy/upstream model ID.
				body: { service_tier: speed.body!.service_tier },
			});
		}
	}
	return [...result.values()].sort((left, right) =>
		left.id.localeCompare(right.id),
	);
}

export default {
	id: "cli-proxy-api",
	async setup(ctx) {
		const baseURL = String(
			ctx.options.baseUrl ?? "http://127.0.0.1:8317/v1",
		).replace(/\/+$/, "");
		const controller = new AbortController();
		let inventory: ProxyModel[] | undefined;
		let timer: ReturnType<typeof setTimeout> | undefined;
		await ctx.model.transform((editor) => {
			if (!inventory) return;
			// Read both source definitions and earlier model edits from this rebuild,
			// including templates for providers without a direct connection.
			const definitions = ["openai", "anthropic", "google"].flatMap((id) => [
				...(editor.provider.get(id)?.models.values() ?? []),
			]);
			const catalog = [
				...new Map(
					[
						...definitions,
						...editor.list().filter((model) => model.providerID !== providerID),
					].map((model) => [`${model.providerID}/${model.id}`, model]),
				).values(),
			];
			const models = projectProxyModels(inventory, catalog);
			for (const model of editor.list(providerID))
				editor.remove(providerID, model.id);
			for (const model of models)
				editor.update(providerID, model.id, (draft) =>
					Object.assign(draft, model),
				);
		});
		const refreshInventory = async () => {
			if (controller.signal.aborted) return;
			try {
				const response = await fetch(`${baseURL}/models?metadata=true`, {
					signal: AbortSignal.any([
						controller.signal,
						AbortSignal.timeout(10_000),
					]),
				});
				if (!response.ok)
					throw new Error(`Model listing failed (${response.status})`);
				const payload = (await response.json()) as {
					data?: ProxyModel[];
				} | null;
				if (
					!Array.isArray(payload?.data) ||
					payload.data.some(
						(entry) =>
							!entry || typeof entry.id !== "string" || !entry.id.trim(),
					)
				)
					throw new Error("Model listing has an invalid data array");
				if (controller.signal.aborted) return;
				payload.data.sort((left, right) => left.id.localeCompare(right.id));
				if (JSON.stringify(payload.data) === JSON.stringify(inventory)) return;
				inventory = payload.data;
				await ctx.model.reload();
			} catch (error) {
				if (!controller.signal.aborted)
					console.warn(
						`[cli-proxy-api] Model refresh failed: ${error instanceof Error ? error.message : String(error)}`,
					);
			} finally {
				if (!controller.signal.aborted)
					timer = setTimeout(refreshInventory, 180_000);
			}
		};
		await refreshInventory();
		return () => {
			controller.abort();
			clearTimeout(timer);
		};
	},
};
