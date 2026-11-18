import { Error as ToolError } from "@opencode/plugin/promise/tool";
import type { Context } from "@opencode/plugin/promise/plugin";
import { homedir } from "node:os";
import path from "node:path";
import { loadBridge, quote, type Payload, type Source } from "./bridge";

type Session = {
	payload: Payload;
	context: string[];
	child: boolean;
	active: boolean;
	ready: Promise<void>;
};
type Shell = {
	payload: Payload;
	background: boolean;
	result?: { status: string; exit?: number };
};

export default {
	id: "codex-plugin-hooks",
	async setup(ctx: Context) {
		const bridge = await loadBridge({
			plugins: ctx.options.plugins as Source[],
			shell: ctx.options.shell as string,
			path: ctx.options.path as string | undefined,
			stateRoot: path.join(
				process.env.XDG_STATE_HOME ?? path.join(homedir(), ".local/state"),
				"opencode/codex-plugins",
			),
		});
		const sessions = new Map<string, Session>();
		const shells = new Map<string, Shell>();
		// The process can exit before the shell tool reports its ID via progress.
		// Retain unmatched exits only while native tool invocations are pending.
		const earlyExits = new Map<string, NonNullable<Shell["result"]>>();
		let callsInFlight = 0;
		const warn = (error: unknown) => console.warn("[codex-hooks]", error);
		const payload = (sessionID: string): Payload => ({
			session_id: sessionID,
			cwd: ctx.location.directory,
		});
		const toolPayload = (
			sessionID: string,
			tool: string,
			input: unknown,
		): Payload => ({
			...payload(sessionID),
			tool_name: tool === "shell" ? "Bash" : tool,
			tool_input: input,
		});
		const runTool = (event: string, input: Payload) =>
			bridge.run(event, input, input.tool_name).catch(warn);
		const start = async (sessionID: string) => {
			let session = sessions.get(sessionID);
			if (!session) {
				session = {
					payload: payload(sessionID),
					context: [],
					child: false,
					active: false,
					ready: Promise.resolve(),
				};
				sessions.set(sessionID, session);
				const current = session;
				current.ready = (async () => {
					const data = await ctx.session.get({ sessionID });
					current.payload.agent_type = data.agent;
					current.child = Boolean(data.parentID);
					current.context = await bridge.run("SessionStart", current.payload);
					if (current.child)
						current.context.push(
							...(await bridge.run(
								"SubagentStart",
								current.payload,
								data.agent ?? "",
							)),
						);
				})();
			}
			await session.ready;
			session.active = session.child;
			return session;
		};
		const stopChild = async (session: Session) => {
			if (!session.child || !session.active) return;
			session.active = false;
			await bridge.run(
				"SubagentStop",
				session.payload,
				session.payload.agent_type,
			);
		};
		const stop = async (sessionID: string) => {
			const session = sessions.get(sessionID);
			if (!session) return;
			sessions.delete(sessionID);
			for (const [id, shell] of shells)
				if (shell.payload.session_id === sessionID) shells.delete(id);
			await session.ready.catch(warn);
			try {
				await stopChild(session);
			} finally {
				await bridge.run("SessionEnd", session.payload);
			}
		};
		const finishBackground = async (id: string) => {
			const shell = shells.get(id);
			if (!shell?.background || !shell.result) return;
			shells.delete(id);
			if (shell.result.status === "exited" && shell.result.exit === 0)
				await runTool("PostToolUse", shell.payload);
		};
		const registrations = [];
		registrations.push(
			await ctx.session.hook("context", async (event) => {
				// Only execute.before may reject. Keep a failed startup recorded so the
				// next tool is blocked even if context assembly cannot surface an error.
				try {
					const session = await start(event.sessionID);
					for (const text of session.context)
						event.system.push({ type: "text", text });
				} catch (error) {
					warn(error);
				}
			}),
		);
		registrations.push(
			await ctx.tool.hook("execute.before", async (event) => {
				try {
					await start(event.sessionID);
					const input = toolPayload(event.sessionID, event.tool, event.input);
					await bridge.run("PreToolUse", input, input.tool_name);
				} catch (error) {
					throw new ToolError({
						message: error instanceof Error ? error.message : String(error),
					});
				}
			}),
		);
		registrations.push(
			await ctx.tool.hook("execute.after", async (event) => {
				if (event.status !== "completed") return;
				if (event.tool === "shell") {
					const output = event.result.output as
						{ exit?: number; status?: string } | undefined;
					// A running result is handled by shell.exited. Signals, timeouts and
					// nonzero exits must not trigger successful-release cleanup.
					if (output?.status === "running" || output?.exit !== 0) return;
				}
				await runTool(
					"PostToolUse",
					toolPayload(event.sessionID, event.tool, event.input),
				);
			}),
		);
		registrations.push(
			await ctx.tool.transform((editor) => {
				editor.update("shell", (tool) => {
					const execute = tool.execute;
					tool.execute = async (input: any, context) => {
						const env = Object.entries(
							bridge.dutEnvironment(context.sessionID),
						);
						const exports = env
							.map(([key, value]) => `${key}=${quote(value)}`)
							.join(" ");
						let shellID: string | undefined;
						callsInFlight++;
						try {
							const result = await execute(
								exports
									? { ...input, command: `export ${exports}\n${input.command}` }
									: input,
								// Reading context.signal opts into cooperative cancellation.
								// Proxy progress without reading that getter on the tool's behalf.
								new Proxy(context, {
									get: (target, key) =>
										key === "progress"
											? async (update: Record<string, unknown>) => {
													// Associate the original input with the native shell ID.
													if (typeof update.shellID === "string") {
														shellID = update.shellID;
														shells.set(shellID, {
															result:
																shells.get(shellID)?.result ??
																earlyExits.get(shellID),
															payload: toolPayload(
																context.sessionID,
																"shell",
																input,
															),
															background: false,
														});
														earlyExits.delete(shellID);
													}
													await context.progress(update);
												}
											: Reflect.get(target, key, target),
								}),
							);
							if (shellID) {
								const output = result.output as { status?: string } | undefined;
								const shell = shells.get(shellID);
								if (output?.status === "running" && shell) {
									shell.background = true;
									await finishBackground(shellID);
								} else shells.delete(shellID);
							}
							return result;
						} catch (error) {
							if (shellID) shells.delete(shellID);
							throw error;
						} finally {
							if (--callsInFlight === 0) earlyExits.clear();
						}
					};
				});
			}),
		);
		const controller = new AbortController();
		const watching = (async () => {
			for await (const event of ctx.event.subscribe({
				types: [
					"shell.exited",
					"session.deleted",
					"session.execution.succeeded",
					"session.execution.failed",
					"session.execution.interrupted",
				],
				signal: controller.signal,
			})) {
				try {
					if (event.type === "shell.exited") {
						const shell = shells.get(event.data.id);
						if (shell) {
							shell.result = event.data;
							await finishBackground(event.data.id);
						} else if (callsInFlight > 0)
							earlyExits.set(event.data.id, event.data);
					} else if (event.type === "session.deleted")
						await stop(event.data.sessionID);
					else if (
						[
							"session.execution.succeeded",
							"session.execution.failed",
							"session.execution.interrupted",
						].includes(event.type)
					) {
						const session = sessions.get(event.data.sessionID);
						if (session) {
							await session.ready;
							await stopChild(session);
						}
					}
				} catch (error) {
					warn(error);
				}
			}
		})().catch((error) => {
			if (!controller.signal.aborted) warn(error);
		});
		return async () => {
			controller.abort();
			await watching;
			await Promise.all(
				registrations.map((registration) =>
					Promise.resolve()
						.then(() => registration.dispose())
						.catch(warn),
				),
			);
			await Promise.all([...sessions.keys()].map((id) => stop(id).catch(warn)));
		};
	},
};
