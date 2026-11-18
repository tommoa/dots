import { afterEach, describe, expect, mock, test } from "bun:test";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
const hooksSource =
  process.env.CODEX_HOOKS_SOURCE ??
  path.resolve(
    import.meta.dir,
    "../modules/home-manager/profiles/development/opencode/codex-hooks",
  );
const { loadBridge, dutSessionID, quote } = await import(
  `${hooksSource}/bridge.ts`
);

// The host provides this module; the bridge itself uses real child processes.
mock.module("@opencode/plugin/promise/tool", () => ({
  Error: class extends Error {
    constructor(input: { message: string }) {
      super(input.message);
    }
  },
}));
const { default: plugin } = await import(`${hooksSource}/index.ts`);
const temporary: string[] = [];
const cleanups: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const cleanup of cleanups.splice(0)) await cleanup();
  for (const dir of temporary.splice(0))
    await rm(dir, { recursive: true, force: true });
});
async function fixture(hooks: Record<string, unknown>) {
  const root = await mkdtemp(path.join(tmpdir(), "opencode-hooks-"));
  temporary.push(root);
  const file = path.join(root, "hooks.json");
  await writeFile(file, JSON.stringify({ hooks }));
  return { name: "dut", root, file };
}
const group = (command: string, matcher?: string, timeout?: number) => [
  { matcher, hooks: [{ type: "command", command, timeout }] },
];
const nodeCommand = (code: string) =>
  `${quote(process.execPath)} -e ${quote(code)}`;
const bridgeFor = (source: Awaited<ReturnType<typeof fixture>>) =>
  loadBridge({ plugins: [source], shell: "/bin/sh", stateRoot: source.root });
const payload = (session_id = "session-one") => ({
  session_id,
  cwd: tmpdir(),
  tool_input: { command: "a dut release lab1" },
});

describe("Codex command hook bridge", () => {
  test("blocks denial, ask, exit 2, malformed output and timeout", async () => {
    const cases: [string, string, number][] = [
      [
        nodeCommand(
          `console.log(JSON.stringify({hookSpecificOutput:{permissionDecision:'deny',permissionDecisionReason:'occupied'}}))`,
        ),
        "occupied",
        2,
      ],
      [
        nodeCommand(
          `console.log(JSON.stringify({hookSpecificOutput:{permissionDecision:'ask'}}))`,
        ),
        "blocked execution",
        2,
      ],
      ["echo blocked >&2; exit 2", "blocked", 2],
      ["echo bad-json", "expected JSON", 2],
      ["sleep 5", "timed out", 0.08],
    ];
    for (const [command, reason, timeout] of cases) {
      const bridge = await bridgeFor(
        await fixture({ PreToolUse: group(command, "Bash", timeout) }),
      );
      await expect(bridge.run("PreToolUse", payload(), "Bash")).rejects.toThrow(
        reason,
      );
    }
  });
});

// Minimal host, with actual asynchronous event iteration and subprocess hooks.
async function host(
  source: Awaited<ReturnType<typeof fixture>>,
  child = false,
) {
  const hooks: Record<string, (event: any) => Promise<void>> = {};
  const events: any[] = [];
  let wake: (() => void) | undefined;
  let transformed: any;
  let implementation: (
    input: any,
    context: any,
  ) => Promise<any> = async () => ({ output: { exit: 0 } });
  const ctx = {
    options: { plugins: [source], shell: "/bin/sh" },
    location: { directory: source.root },
    session: {
      // The promise plugin API returns Session.Info directly, without an HTTP envelope.
      get: async () => ({
        parentID: child ? "parent" : undefined,
        agent: "dut-triager",
      }),
      hook: async (name: string, cb: any) => {
        hooks[name] = cb;
        return { dispose: async () => {} };
      },
    },
    tool: {
      hook: async (name: string, cb: any) => {
        hooks[name] = cb;
        return { dispose: async () => {} };
      },
      transform: async (cb: any) => {
        transformed = {
          execute: (...args: any[]) => implementation(args[0], args[1]),
        };
        cb({ update: (_name: string, update: any) => update(transformed) });
        return { dispose: async () => {} };
      },
    },
    event: {
      subscribe: async function* ({ signal }: { signal: AbortSignal }) {
        signal.addEventListener("abort", () => wake?.());
        while (!signal.aborted) {
          if (events.length) yield events.shift();
          else
            await new Promise<void>((resolve) => {
              wake = resolve;
            });
        }
      },
    },
  };
  const cleanup = await plugin.setup(ctx as any);
  cleanups.push(cleanup);
  return {
    hooks,
    cleanup,
    emit: (type: string, data: any) => {
      events.push({ type, data });
      wake?.();
    },
    implement: (fn: typeof implementation) => {
      implementation = fn;
    },
    execute: (input: any, sessionID = "session-one") =>
      transformed.execute(input, {
        sessionID,
        progress: async () => {},
        signal: new AbortController().signal,
      }),
  };
}
const event = (
  input: unknown = { command: "a dut release lab1" },
  extra = {},
) => ({ sessionID: "session-one", tool: "shell", input, ...extra });
async function lines(file: string) {
  try {
    return (await readFile(file, "utf8")).trim().split("\n").filter(Boolean);
  } catch {
    return [];
  }
}
const settle = async (check: () => Promise<boolean>) => {
  for (let i = 0; i < 100; i++) {
    if (await check()) return;
    await Bun.sleep(10);
  }
  throw new Error("event did not settle");
};

describe("OpenCode lifecycle adapter", () => {
  test("rejects tools on startup failure without rejecting context assembly", async () => {
    const h = await host(await fixture({ SessionStart: group("exit 2") }));
    await h.hooks.context({ sessionID: "session-one", system: [] });
    await expect(h.hooks["execute.before"](event())).rejects.toThrow("exit 2");
  });
  test("keeps original input for hook validation and isolates shell environments", async () => {
    const source = await fixture({ PreToolUse: group("exit 2", "Bash") });
    const h = await host(source);
    await expect(h.hooks["execute.before"](event())).rejects.toThrow();
    const inputs: any[] = [];
    h.implement(async (input) => {
      inputs.push(input);
      return { output: { exit: 0 } };
    });
    const input = { command: "echo hello" };
    await Promise.all([
      h.execute(input, "session-one"),
      h.execute(input, "session-two"),
    ]);
    expect(input.command).toBe("echo hello");
    expect(inputs[0].command).toContain(
      `DUT_PLUGIN_SESSION_ID='${dutSessionID("session-one")}'`,
    );
    expect(inputs[1].command).toContain(
      `DUT_PLUGIN_SESSION_ID='${dutSessionID("session-two")}'`,
    );
  });
  test("runs post-tool only for successful releases, including a background completion race", async () => {
    const source = await fixture({});
    const log = path.join(source.root, "post.log");
    await writeFile(
      source.file,
      JSON.stringify({
        hooks: { PostToolUse: group(`echo post >> ${quote(log)}`, "Bash") },
      }),
    );
    const h = await host(source);
    for (const output of [
      { exit: 1 },
      { signal: "SIGTERM" },
      { status: "running", shellID: "sh_x" },
    ])
      await h.hooks["execute.after"](
        event(undefined, { status: "completed", result: { output } }),
      );
    await h.hooks["execute.after"](event(undefined, { status: "error" }));
    expect(await lines(log)).toEqual([]);
    await h.hooks["execute.after"](
      event(undefined, {
        status: "completed",
        result: { output: { exit: 0 } },
      }),
    );
    let expectedPosts = 1;
    for (const early of ["before-progress", "before-return", "after-return"]) {
      const id = `sh_${early}`;
      h.implement(async (_input, context) => {
        if (early === "before-progress") {
          h.emit("shell.exited", { id, status: "exited", exit: 0 });
          await Bun.sleep(20);
        }
        await context.progress({ shellID: id });
        if (early === "before-return") {
          h.emit("shell.exited", { id, status: "exited", exit: 0 });
          await Bun.sleep(20);
        }
        return { output: { status: "running", shellID: id } };
      });
      await h.execute({ command: "a dut release lab1" });
      if (early === "after-return")
        h.emit("shell.exited", { id, status: "exited", exit: 0 });
      expectedPosts++;
      await settle(async () => (await lines(log)).length === expectedPosts);
    }
    expect(await lines(log)).toEqual(["post", "post", "post", "post"]);
  });
  test("stops child runs once, keeps idle sessions, cleans deletion and shutdown even after stop failure", async () => {
    const source = await fixture({});
    const log = path.join(source.root, "lifecycle.log");
    await writeFile(
      source.file,
      JSON.stringify({
        hooks: {
          SubagentStart: group(
            `echo '{"hookSpecificOutput":{"additionalContext":"triage context"}}'`,
            "dut-triager",
          ),
          SubagentStop: group(
            `echo child >> ${quote(log)}; exit 2`,
            "dut-triager",
          ),
          SessionEnd: group(`echo end >> ${quote(log)}`),
        },
      }),
    );
    const h = await host(source, true);
    const system: any[] = [];
    await h.hooks.context({ sessionID: "session-one", system });
    expect(system).toEqual([{ type: "text", text: "triage context" }]);
    h.emit("session.status", {
      sessionID: "session-one",
      status: { type: "idle" },
    });
    await Bun.sleep(20);
    expect(await lines(log)).toEqual([]);
    h.emit("session.execution.succeeded", { sessionID: "session-one" });
    await settle(async () => (await lines(log)).length === 1);
    h.emit("session.deleted", { sessionID: "session-one" });
    await settle(async () => (await lines(log)).length === 2);
    expect(await lines(log)).toEqual(["child", "end"]);
    await h.hooks["execute.before"](event(undefined, { sessionID: "second" }));
    await h.cleanup();
    expect(await lines(log)).toEqual(["child", "end", "child", "end"]);
  });
});

const upstream = JSON.parse(process.env.CODEX_HOOKS_PLUGINS ?? "[]").find(
  (plugin: { name: string }) => plugin.name === "dut",
);
(upstream ? test : test.skip)(
  "upstream DUT hooks block unsafe commands and clean only this session using fake tmux",
  async () => {
    const source = await fixture({});
    const fakeBin = path.join(source.root, "bin");
    await mkdir(fakeBin);
    const calls = path.join(source.root, "tmux.log");
    await writeFile(
      path.join(fakeBin, "tmux"),
      `#!/bin/sh\necho "$*" >> ${quote(calls)}\nif [ "$1" = list-sessions ]; then printf '%s\\n' dut-${dutSessionID("session-one").slice(0, 12)}-lab1-console dut-other-lab1-console; fi\n`,
      { mode: 0o755 },
    );
    const bridge = await loadBridge({
      plugins: [upstream],
      stateRoot: source.root,
      path: fakeBin,
      shell: "/bin/sh",
    });
    // Sessions created together share a timestamp prefix; their DUT tags must differ.
    expect(
      bridge.dutEnvironment("ses_12345678AAAAAAAAAAAAAAAAAA")
        .DUT_PLUGIN_SESSION_TAG,
    ).not.toBe(
      bridge.dutEnvironment("ses_12345678BBBBBBBBBBBBBBBBBB")
        .DUT_PLUGIN_SESSION_TAG,
    );
    await bridge.run("SessionStart", payload());
    await expect(
      bridge.run(
        "PreToolUse",
        {
          ...payload(),
          tool_input: { command: "a dut ssh lab1 show version" },
        },
        "Bash",
      ),
    ).rejects.toThrow("dut.bash");
    // Force the ownership lookup to fail locally; never contact a real DUT service.
    await writeFile(
      path.join(fakeBin, "RdamDut.py"),
      "def RdamDut(*args):\n    raise ValueError('test fixture: no console configured')\n",
    );
    const previousPythonPath = process.env.PYTHONPATH;
    try {
      process.env.PYTHONPATH = fakeBin;
      await expect(
        bridge.run(
          "PreToolUse",
          { ...payload(), tool_input: { command: "a dut attach lab1" } },
          "Bash",
        ),
      ).rejects.toThrow("could not verify");
    } finally {
      if (previousPythonPath === undefined) delete process.env.PYTHONPATH;
      else process.env.PYTHONPATH = previousPythonPath;
    }
    await bridge.run("PostToolUse", payload(), "Bash");
    expect(await lines(calls)).toContain(
      `kill-session -t dut-${dutSessionID("session-one").slice(0, 12)}-lab1-console`,
    );
    expect(
      (await lines(calls)).some((s) => s.includes("kill-session -t dut-other")),
    ).toBe(false);
    await bridge.run("SessionEnd", payload());
  },
);
