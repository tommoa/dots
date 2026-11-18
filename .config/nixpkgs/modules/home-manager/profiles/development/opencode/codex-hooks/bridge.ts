import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

type Hook = { type: string; command: string; timeout?: number };
type Group = { matcher?: string; hooks: Hook[] };
export type Source = { name: string; root: string; file: string };
export type Payload = {
	session_id: string;
	cwd: string;
	tool_name?: string;
	tool_input?: unknown;
	agent_type?: string;
};
const events = new Set([
	"SessionStart",
	"SessionEnd",
	"PreToolUse",
	"PostToolUse",
	"SubagentStart",
	"SubagentStop",
]);
export const quote = (value: string) => `'${value.replaceAll("'", "'\\''")}'`;
// OpenCode IDs start with timestamps. DUT truncates IDs to 12-character tags,
// so using the raw prefix would merge sessions created close together.
export const dutSessionID = (value: string) =>
	createHash("sha256").update(value).digest("hex");

export class HookFailure extends Error {}

// Hook programs are trusted, pinned upstream code. Time and output limits also
// apply to their descendants, so a stuck command cannot hold a tool indefinitely.
async function execute(
	command: string,
	shell: string,
	env: NodeJS.ProcessEnv,
	cwd: string,
	timeout: number,
	input: string,
) {
	return new Promise<{ stdout: string; stderr: string; code: number }>(
		(resolve, reject) => {
			const child = spawn(shell, ["-c", command], {
				cwd,
				env,
				detached: true,
				stdio: "pipe",
			});
			let stdout = "",
				stderr = "",
				failure: string | undefined;
			const stop = (reason: string) => {
				failure = reason;
				if (child.pid) {
					try {
						process.kill(-child.pid, "SIGKILL");
					} catch {
						/* already exited */
					}
				}
			};
			const timer = setTimeout(() => stop("Hook timed out"), timeout * 1000);
			child.stdout.on("data", (data) => {
				stdout += data;
				if (stdout.length + stderr.length > 65536)
					stop("Hook output exceeded 64 KiB");
			});
			child.stderr.on("data", (data) => {
				stderr += data;
				if (stdout.length + stderr.length > 65536)
					stop("Hook output exceeded 64 KiB");
			});
			child.on("error", (error) => {
				clearTimeout(timer);
				reject(error);
			});
			child.on("close", (code) => {
				clearTimeout(timer);
				if (failure) reject(new HookFailure(failure));
				else resolve({ stdout, stderr, code: code ?? 1 });
			});
			child.stdin.on("error", () => {});
			child.stdin.end(input);
		},
	);
}

export async function loadBridge(options: {
	plugins: Source[];
	shell: string;
	path?: string;
	stateRoot: string;
}) {
	const sources = await Promise.all(
		options.plugins.map(async (source) => {
			const { hooks } = JSON.parse(await readFile(source.file, "utf8")) as {
				hooks: Record<string, Group[]>;
			};
			if (!hooks || typeof hooks !== "object" || Array.isArray(hooks))
				throw new Error(`Invalid hook manifest: ${source.name}`);
			for (const [event, groups] of Object.entries(hooks)) {
				if (!events.has(event))
					throw new Error(
						`Unsupported Codex hook event: ${source.name}/${event}`,
					);
				if (!Array.isArray(groups))
					throw new Error(`Invalid hook groups: ${source.name}/${event}`);
				for (const group of groups) {
					if (
						!Array.isArray(group.hooks) ||
						(group.matcher !== undefined && typeof group.matcher !== "string")
					)
						throw new Error(`Invalid hook group: ${source.name}/${event}`);
					if (group.matcher && group.matcher !== "*")
						new RegExp(`^(?:${group.matcher})$`);
					for (const hook of group.hooks) {
						if (
							hook.type !== "command" ||
							typeof hook.command !== "string" ||
							(hook.timeout !== undefined &&
								(!Number.isFinite(hook.timeout) || hook.timeout <= 0))
						)
							throw new Error(
								`Unsupported Codex hook handler: ${source.name}/${event}`,
							);
					}
				}
			}
			return { ...source, hooks };
		}),
	);
	return {
		async run(event: string, payload: Payload, matcher = "") {
			const context: string[] = [];
			for (const source of sources) {
				for (const group of source.hooks[event] ?? []) {
					if (
						group.matcher &&
						group.matcher !== "*" &&
						!new RegExp(`^(?:${group.matcher})$`).test(matcher)
					)
						continue;
					for (const hook of group.hooks) {
						const hookPayload =
							source.name === "dut"
								? { ...payload, session_id: dutSessionID(payload.session_id) }
								: payload;
						const env: NodeJS.ProcessEnv = {
							...process.env,
							PLUGIN_ROOT: source.root,
							CLAUDE_PLUGIN_ROOT: source.root,
							PLUGIN_DATA: path.join(options.stateRoot, source.name),
							CODEX_THREAD_ID: hookPayload.session_id,
							PATH: [options.path, process.env.PATH]
								.filter(Boolean)
								.join(path.delimiter),
						};
						// A Codex hook must not append exports to a live Claude session.
						delete env.CLAUDE_ENV_FILE;
						const result = await execute(
							hook.command,
							options.shell,
							env,
							payload.cwd,
							hook.timeout ?? 10,
							JSON.stringify({ ...hookPayload, hook_event_name: event }),
						);
						if (result.code !== 0)
							throw new HookFailure(
								`${source.name}/${event}: ${result.stderr.trim() || `exit ${result.code}`}`,
							);
						if (result.stderr.trim())
							console.warn(
								`[codex-hooks] ${source.name}/${event}: ${result.stderr.trim()}`,
							);
						if (!result.stdout.trim()) continue;
						let output;
						try {
							output = JSON.parse(result.stdout);
						} catch {
							throw new HookFailure(
								`${source.name}/${event}: expected JSON hook output`,
							);
						}
						const specific = output.hookSpecificOutput;
						if (
							output.continue === false ||
							specific?.permissionDecision === "deny" ||
							specific?.permissionDecision === "ask"
						)
							throw new HookFailure(
								specific?.permissionDecisionReason ??
									output.stopReason ??
									`${source.name}/${event} blocked execution`,
							);
						if (typeof specific?.additionalContext === "string")
							context.push(specific.additionalContext);
					}
				}
			}
			return context;
		},
		// DUT's upstream runner and its shell helpers share this session layout.
		// Keep this explicit until upstream supplies a native OpenCode hook port.
		dutEnvironment(sessionID: string) {
			if (!sources.some((source) => source.name === "dut")) return {};
			const id = dutSessionID(sessionID),
				root = path.join(options.stateRoot, "dut");
			return {
				DUT_PLUGIN_SESSION_ID: id,
				DUT_PLUGIN_SESSION_TAG: id.slice(0, 12),
				DUT_PLUGIN_RUNTIME_ROOT: root,
				DUT_PLUGIN_LOG_DIR:
					process.env.DUT_PLUGIN_LOG_DIR || path.join(root, id, "logs"),
				DUT_TRIAGE_DIR:
					process.env.DUT_TRIAGE_DIR || path.join(root, id, "dut"),
			};
		},
	};
}
