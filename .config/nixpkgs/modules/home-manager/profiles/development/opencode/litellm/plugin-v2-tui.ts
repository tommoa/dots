import type { TuiPlugin } from "@opencode-ai/plugin/tui";

const message = "LiteLLM is using the OpenCode v1 compatibility shim. When v2 setup() loads in production, remove the shim.";

const tui: TuiPlugin = async (api) => {
	api.ui.toast({
		variant: "warning",
		title: "LiteLLM plugin",
		message,
		duration: 10_000,
	});
};

export default {
	id: "litellm-status",
	tui,
};
