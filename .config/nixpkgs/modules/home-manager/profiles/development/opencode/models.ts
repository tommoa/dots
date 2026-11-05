import type { Model } from "@opencode/schema/model";
import type { Types } from "effect";
import type { LiteLLMRoute } from "../ai-providers/routing";

// Model metadata shared by direct LiteLLM and CLIProxyAPI. Transport identity,
// credentials and endpoints belong to their respective provider adapters.
export type ModelMetadata = Omit<
	Types.DeepMutable<typeof Model.Info.Encoded>,
	"modelID" | "providerID" | "canonical" | keyof typeof Model.Overlays
>;

export type ModelVariant = ModelMetadata["variants"][number];
export type ModelCostTier = ModelMetadata["cost"][number];

export function toReasoningVariants(
	efforts: readonly string[],
	route: LiteLLMRoute,
): ModelVariant[] {
	return efforts.map((effort) => ({
		id: effort,
		settings: {
			reasoningEffort: effort,
			...(route === "responses"
				? {
						reasoningSummary: "auto",
						include: ["reasoning.encrypted_content"],
					}
				: {}),
		},
	}));
}
