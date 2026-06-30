export type LiteLLMRoute = "chat" | "responses";

export interface LiteLLMRouteOverrides {
	responses?: Iterable<string>;
	chat?: Iterable<string>;
}

export interface LiteLLMParams {
	model?: string | null;
	custom_llm_provider?: string | null;
	litellm_provider?: string | null;
	api_base?: string | null;
}

export interface LiteLLMModelInfo {
	mode?: string | null;
	base_model?: string | null;
	litellm_provider?: string | null;
	custom_llm_provider?: string | null;
	max_tokens?: number;
	max_input_tokens?: number;
	max_output_tokens?: number;
	input_cost_per_token?: number;
	output_cost_per_token?: number;
	cache_read_input_token_cost?: number;
	cache_creation_input_token_cost?: number;
	supports_function_calling?: boolean | null;
	supports_reasoning?: boolean | null;
	supports_vision?: boolean | null;
	supports_pdf_input?: boolean | null;
	supports_audio_input?: boolean | null;
	supports_audio_output?: boolean | null;
	supported_openai_params?: string[];
	release_date?: string;
	releaseDate?: string;
}

export interface LiteLLMModelEntry extends LiteLLMModelInfo {
	id?: string;
	name?: string;
	model_name?: string;
	model_group?: string;
	context_window?: number;
	litellm_params?: LiteLLMParams;
	model_info?: LiteLLMModelInfo;
}

export interface LiteLLMRouteMatch {
	providerPackage?: string;
	api?: string;
}

export interface LiteLLMRouteOptions {
	routeOverrides?: LiteLLMRouteOverrides;
	match?: LiteLLMRouteMatch;
}

const responseParams = new Set(["verbosity", "safety_identifier"]);

export function classifyLiteLLMRoute(entry: LiteLLMModelEntry, options: LiteLLMRouteOptions = {}): LiteLLMRoute {
	const id = entryID(entry) ?? "";
	const info = modelInfo(entry);
	const chatOverrides = new Set(options.routeOverrides?.chat ?? []);
	const responsesOverrides = new Set(options.routeOverrides?.responses ?? []);

	if (chatOverrides.has(id)) return "chat";
	if (responsesOverrides.has(id)) return "responses";
	if (info.mode === "responses") return "responses";
	if (options.match?.providerPackage === "@ai-sdk/openai") return "responses";
	if (options.match?.api === "openai-responses") return "responses";
	if (isGpt5ReasoningModel(id, info)) return "responses";
	if (hasResponsesParam(info)) return "responses";
	return "chat";
}

export function entryID(entry: LiteLLMModelEntry) {
	return entry.model_name ?? entry.id ?? entry.model_group;
}

export function modelInfo(entry: LiteLLMModelEntry): LiteLLMModelInfo {
	return entry.model_info ?? entry;
}

export function stripProviderPrefix(id?: string | null) {
	if (!id) return;
	const slashIndex = id.indexOf("/");
	return slashIndex === -1 ? id : id.slice(slashIndex + 1);
}

export function canonicalModelID(id: string) {
	return splitDateSuffix(id).baseID;
}

export function splitDateSuffix(id: string) {
	const match = id.match(/^(.+?)-(\d{4})(\d{2})(\d{2})$/);
	if (!match) return { baseID: id };
	const month = Number(match[3]);
	const day = Number(match[4]);
	if (month < 1 || month > 12 || day < 1 || day > 31) return { baseID: id };
	return { baseID: match[1], releaseDate: `${match[2]}-${match[3]}-${match[4]}`, displayDate: { month, day } };
}

function hasResponsesParam(info: LiteLLMModelInfo) {
	return info.supported_openai_params?.some((param) => responseParams.has(param)) ?? false;
}

function isGpt5ReasoningModel(id: string, info: LiteLLMModelInfo) {
	return supportsReasoningEffort(info) && [id, info.base_model].some((value) => isGpt5FamilyModel(value));
}

function supportsReasoningEffort(info: LiteLLMModelInfo) {
	return info.supported_openai_params?.includes("reasoning_effort") ?? false;
}

function isGpt5FamilyModel(id?: string | null) {
	if (!id) return false;
	const stripped = stripProviderPrefix(id);
	return Boolean(stripped && canonicalModelID(stripped).toLowerCase().startsWith("gpt-5"));
}
