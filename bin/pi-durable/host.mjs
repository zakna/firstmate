#!/usr/bin/env node
// Firstmate pi-durable pilot host: one task worker on @earendil-works/pi-durable.
//
// This is an opt-in worker runtime, separate from the pi and pi-signed CLI
// adapters. bin/fm-pi-durable.sh owns installing the pinned dependencies and
// launching this file; bin/fm-spawn.sh owns the per-task arguments. The
// adapter contract (busy source, composer, control verbs, relaunch, store
// retention) is owned by .agents/skills/harness-adapters/references/harness/pi-durable.md.
//
// Ownership decisions this host makes:
// - The per-task SQLite store under --store is the ONE recovery authority for
//   the conversation. Reopening the same store on relaunch resumes the same
//   conversation; nothing else replays work.
// - The launch brief is admitted with a requestId derived from its exact
//   text, so a relaunch that hands the same brief again finds the existing
//   submission instead of starting the task twice, while a changed brief is
//   admitted as new input.
// - The steering inbox ($FM_TASK_INBOX, bin/fm-task-inbox-lib.sh) is bridged
//   into durable input: on every submitted terminal row, and once at open,
//   each unhandled NNN.msg is admitted in numeric order with a requestId
//   derived from its name and bytes, so a re-rung doorbell or a relaunch never
//   delivers one message twice. The host acknowledges each message (the move
//   into handled/) once the store has admitted it, and the doorbell line
//   itself is never model input.
// - Only `read` is replay-safe. Every side-effecting tool (bash, write, edit)
//   keeps pi-durable's default unsafe policy: a call interrupted by a crash is
//   never executed again; the model gets the committed interrupted result.
// - Models come only from an explicit openai-completions provider declared in
//   a Pi-format models.json, with that provider's compat flags. OAuth
//   providers are refused: this pilot has no credential bridge.
//
// Usage:
//   host.mjs --runtime <dir> --store <dir> --cwd <dir> --model <provider/id>
//            --models-json <file> [--brief <text>]
//            [--busy-cmd <fm-busy-event.sh> --busy-state <dir> --busy-id <id> --busy-gen <gen>]
//            [--turnend <file>]
//   host.mjs --check --runtime <dir>       verify the pinned runtime loads
//
// Terminal contract (what Firstmate's control plane drives):
// - The composer is the bare row `⟫ ` plus typed text; Enter submits the row.
//   A row submitted while a run is busy steers that run; otherwise it starts one.
// - Escape aborts the current run (queued inputs are withdrawn).
// - `/quit` (or Ctrl-D on an empty row) closes the store and exits 0.
import { chmodSync, closeSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, statSync, utimesSync } from "node:fs";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import * as readline from "node:readline";

process.title = "pi-durable";
const PROMPT = "⟫ ";
const DOORBELL = ": Firstmate instruction waiting:";

function fail(message) {
	process.stderr.write(`pi-durable: error: ${message}\n`);
	process.exit(1);
}

function parseArgs(argv) {
	const out = {};
	const flags = new Set(["check"]);
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (!arg.startsWith("--")) fail(`unexpected argument: ${arg}`);
		const key = arg.slice(2);
		if (flags.has(key)) {
			out[key] = true;
			continue;
		}
		const value = argv[i + 1];
		if (value === undefined) fail(`${arg} needs a value`);
		out[key] = value;
		i++;
	}
	return out;
}

const args = parseArgs(process.argv.slice(2));
if (!args.runtime) fail("--runtime is required");
const runtime = resolve(args.runtime);
let loader;
try {
	loader = await import(pathToFileURL(join(runtime, "load.mjs")).href);
} catch {
	fail(`no pinned runtime in ${runtime}; run bin/fm-pi-durable.sh install`);
}
const load = (spec) => loader.load(spec).catch((error) => fail(`pinned runtime cannot load ${spec}: ${error.message}`));

const durable = await load("@earendil-works/pi-durable");
const durableTools = await load("@earendil-works/pi-durable/tools");
const durableEnv = await load("@earendil-works/pi-durable/env/node");
const durableSqlite = await load("@earendil-works/pi-durable/storage/sqlite/node");
const ai = await load("@earendil-works/pi-ai");
const completions = await load("@earendil-works/pi-ai/api/openai-completions.lazy");
const chordContext = await load("@earendil-works/chord/context");
if (args.check) {
	const lock = JSON.parse(readFileSync(join(runtime, "package-lock.json"), "utf8"));
	const version = lock.packages?.["node_modules/@earendil-works/pi-durable"]?.version;
	process.stdout.write(`pi-durable runtime ok: @earendil-works/pi-durable ${version}\n`);
	process.exit(0);
}

for (const required of ["store", "cwd", "model", "models-json"]) {
	if (!args[required]) fail(`--${required} is required`);
}
if (args.thinking !== undefined) {
	fail("--thinking is not supported by the pi-durable pilot; thinking levels are not translated");
}
const cwd = resolve(args.cwd);
const slash = args.model.indexOf("/");
if (slash <= 0 || slash === args.model.length - 1) fail(`--model must be <provider>/<id>, got ${args.model}`);
const providerId = args.model.slice(0, slash);
const modelId = args.model.slice(slash + 1);

// Translate one declared openai-completions provider/model, refusing anything
// the pilot cannot carry faithfully instead of choosing a fallback.
function declaredModel() {
	let catalog;
	try {
		catalog = JSON.parse(readFileSync(args["models-json"], "utf8"));
	} catch (error) {
		fail(`cannot read --models-json ${args["models-json"]}: ${error.message}`);
	}
	const provider = catalog?.providers?.[providerId];
	if (provider === undefined) {
		fail(`provider ${providerId} is not declared in ${args["models-json"]}; OAuth providers have no credential bridge in this pilot`);
	}
	if (provider.api !== "openai-completions") {
		fail(`provider ${providerId} uses api ${provider.api ?? "(none)"}; the pilot supports only openai-completions`);
	}
	if (typeof provider.baseUrl !== "string" || provider.baseUrl === "") fail(`provider ${providerId} has no baseUrl`);
	const entry = (provider.models ?? []).find((m) => m.id === modelId);
	if (entry === undefined) fail(`model ${modelId} is not declared under provider ${providerId}`);
	const apiKey = typeof provider.apiKey === "string" ? (process.env[provider.apiKey] ?? provider.apiKey) : undefined;
	const model = {
		id: entry.id,
		name: entry.name ?? entry.id,
		api: "openai-completions",
		provider: providerId,
		baseUrl: entry.baseUrl ?? provider.baseUrl,
		reasoning: entry.reasoning === true,
		input: entry.input ?? ["text"],
		cost: entry.cost ?? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: entry.contextWindow ?? 128000,
		maxTokens: entry.maxTokens ?? 16384,
		compat: { ...(provider.compat ?? {}), ...(entry.compat ?? {}) },
	};
	const resolveAuth = async () => ({ auth: apiKey === undefined ? {} : { apiKey } });
	return ai.createProvider({
		id: providerId,
		name: provider.name ?? providerId,
		baseUrl: provider.baseUrl,
		auth: { apiKey: { name: providerId, resolve: resolveAuth } },
		models: [model],
		api: completions.openAICompletionsApi(),
	});
}

const models = ai.createModels();
models.setProvider(declaredModel());
if (models.getModel(providerId, modelId) === undefined) fail(`model ${args.model} did not register`);

// The store holds prompts, tool arguments, and results: owner-only.
process.umask(0o077);
const store = resolve(args.store);
mkdirSync(store, { recursive: true, mode: 0o700 });
chmodSync(store, 0o700);
if ((statSync(store).mode & 0o077) !== 0) fail(`store ${store} is not owner-only`);

const busy = (state, event) =>
	new Promise((done) => {
		if (!args["busy-cmd"]) return done();
		execFile(
			args["busy-cmd"],
			["apply", args["busy-state"], args["busy-id"], state, "--gen", args["busy-gen"], "--source", "pi-durable-host", "--event", event],
			() => done(),
		);
	});
const touchTurnEnd = () => {
	if (!args.turnend) return;
	try {
		const now = new Date();
		closeSync(openSync(args.turnend, "a"));
		utimesSync(args.turnend, now, now);
	} catch {}
};

const context = chordContext.BACKGROUND_CONTEXT;
const tools = durableTools.CodingTools;
const readTool = durableTools.createReadTool();
const Worker = durable.defineExtension({
	name: "firstmate-worker",
	sections: [
		durable.section(
			"preamble",
			() =>
				"You are an autonomous coding agent working in a terminal. " +
				"Use the read, write, edit, and bash tools to do the task the user messages describe, " +
				"without waiting for confirmation. Messages that arrive while you work are steering for the current task. " +
				"New messages, including steering messages, are delivered to you automatically, so never poll, list, or wait for them: " +
				"when the work the latest message asks for is done, reply with one short line and end your turn.",
			{ tag: false },
		),
		durable.section("cwd", (input) => input.env?.cwd),
	],
	// read has no side effects, so a crash mid-read reruns it on reopen.
	wraps: [durable.wrapTool(readTool, (tool) => ({ ...tool, replay: "safe" }))],
});
const registry = durable.createRegistry();
registry.install(tools);
registry.install(Worker);

// ---- terminal --------------------------------------------------------------
// A short escape timeout keeps a lone Escape from swallowing the next typed
// key as a Meta chord, which turned fm-control's Escape-then-`/quit` into `quit`.
const rl = readline.createInterface({ input: process.stdin, output: process.stdout, prompt: PROMPT, terminal: true, escapeCodeTimeout: 50 });
let partial = "";
function log(text) {
	process.stdout.write(`\r\x1b[2K${text}\n`);
	rl.prompt(true);
}
function flushText(delta) {
	partial += delta;
	const lines = partial.split("\n");
	partial = lines.pop() ?? "";
	if (lines.length > 0) log(lines.join("\n"));
}
// Text already shown per content block of the in-flight message, so a delta,
// a whole-block update, and the committed message each print only what is new.
let shown = new Map();
function showText(index, full) {
	const seen = shown.get(index) ?? "";
	if (!full.startsWith(seen)) return;
	shown.set(index, full);
	flushText(full.slice(seen.length));
}
function endText() {
	if (partial !== "") log(partial);
	partial = "";
}
const short = (value, max = 160) => {
	const text = typeof value === "string" ? value : JSON.stringify(value);
	return text.length > max ? `${text.slice(0, max)}…` : text;
};

const storage = await durableSqlite.openNodeSqliteStorage(join(store, "conversation.sqlite"));
const harness = await durable.Harness.open(
	storage,
	{
		models,
		registry,
		env: ({ cwd: agentCwd }) => new durableEnv.NodeExecutionEnv({ cwd: agentCwd ?? cwd }),
		identity: { attribution: null },
		onReport: (error, info) => log(`report ${info.type}: ${error instanceof Error ? error.message : String(error)}`),
	},
	context,
);
const root = await harness.root(context, { agent: { model: { provider: providerId, modelId }, cwd } });
await root.configure({ model: { provider: providerId, modelId }, cwd }, context);

let running = false;
async function setRunning(next, event) {
	if (running === next) return;
	running = next;
	await busy(next ? "busy" : "idle", event);
}

const stream = await durable.watchEvents(harness, root.id, context);
running = stream.snapshot.run !== undefined;
stream.start(async (events) => {
	for (const event of events) {
		switch (event.type) {
			case "snapshot":
				await setRunning(event.run !== undefined, "snapshot");
				break;
			case "run_start":
				await setRunning(true, "run-start");
				break;
			case "run_end":
				endText();
				await setRunning(false, "run-end");
				break;
			case "turn_end":
				endText();
				touchTurnEnd();
				break;
			case "message_start":
				shown = new Map();
				break;
			case "message_update":
				for (const change of event.changes) {
					if (change.type === "text_delta") showText(change.contentIndex, (shown.get(change.contentIndex) ?? "") + change.delta);
					else if ((change.type === "text_start" || change.type === "block") && change.block.type === "text") {
						showText(change.contentIndex, change.block.text);
					}
				}
				break;
			case "message_end": {
				const message = event.entry?.model?.[0];
				if (message?.role === "assistant" && Array.isArray(message.content)) {
					message.content.forEach((block, index) => block.type === "text" && showText(index, block.text));
					// Some local models put the whole closing reply in the reasoning
					// field; a final message with no text and no tool call would
					// otherwise leave the pane silent.
					const final = !message.content.some((block) => block.type === "text" || block.type === "toolCall");
					if (final) message.content.forEach((block) => block.type === "thinking" && block.thinking.trim() && log(block.thinking.trim()));
				}
				endText();
				shown = new Map();
				break;
			}
			case "tool_execution_start":
				endText();
				log(`• ${event.toolName} ${short(event.args)}`);
				break;
			case "tool_execution_end":
				if (event.entry?.data?.isError) log(`  ${event.toolName} failed`);
				break;
			case "submission":
				if (event.record.status === "unanswered") log(`input not answered: ${short(event.record.reason ?? event.record)}`);
				break;
			case "auto_retry_start":
				log(`retrying (${event.attempt}): ${short(event.errorMessage)}`);
				break;
			case "task_failed":
				log(`task failed: ${short(event.message)}`);
				break;
		}
	}
});

if (args.brief !== undefined) {
	const digest = createHash("sha256").update(args.brief).digest("hex");
	await root.submit({ type: "input", content: args.brief, requestId: `fm-launch-brief:${digest}` }, context);
}
// Serialized so admissions from overlapping rows keep the inbox's order.
let inboxChain = Promise.resolve();
function admitInbox() {
	inboxChain = inboxChain.then(async () => {
		const dir = process.env.FM_TASK_INBOX;
		if (!dir) return;
		let names;
		try {
			names = readdirSync(dir).filter((name) => /^[0-9]+\.msg$/.test(name));
		} catch {
			return;
		}
		names.sort((a, b) => Number.parseInt(a, 10) - Number.parseInt(b, 10));
		for (const name of names) {
			const path = join(dir, name);
			let raw;
			try {
				raw = readFileSync(path, "utf8");
			} catch {
				continue; // acknowledged between the listing and the read
			}
			const split = raw.indexOf("\n--\n");
			const body = split === -1 ? raw : raw.slice(split + 4);
			const digest = createHash("sha256").update(raw).digest("hex");
			const content = `Firstmate steering message ${name}:\n\n${body}`;
			try {
				await root.submit({ type: "input", content, whenBusy: "steer", requestId: `fm-inbox:${name}:${digest}` }, context);
			} catch (error) {
				log(`inbox ${name} not admitted: ${error.message}`);
				return; // later messages wait so the conversation keeps the inbox's order
			}
			// Admitted into the durable conversation: that is delivery, so the host
			// acknowledges. A crash before this move re-admits under the same id,
			// which the store answers with the existing submission.
			try {
				mkdirSync(join(dir, "handled"), { recursive: true });
				renameSync(path, join(dir, "handled", name));
			} catch (error) {
				log(`inbox ${name} admitted but not acknowledged: ${error.message}`);
			}
		}
	});
	return inboxChain;
}
await admitInbox();
harness.resume();
// A reopened store with nothing left to run settles idle at once; a live run
// reports busy through its own run_start or snapshot.
if (!running) await busy("idle", "open-settled");

let closing = false;
async function shutdown(code) {
	if (closing) return;
	closing = true;
	rl.close();
	await stream.stop().catch(() => {});
	await harness.close(context).catch(() => {});
	process.exit(code);
}
harness.closed.then((end) => {
	if (end.reason === "failed") {
		process.stderr.write(`pi-durable: store failed: ${end.error?.message ?? end.error}\n`);
		void shutdown(1);
	}
});

readline.emitKeypressEvents(process.stdin, rl);
process.stdin.on("keypress", (_text, key) => {
	if (key?.name === "escape" && running) {
		log("interrupting…");
		void root.abort(context).then(() => log("interrupted"));
	}
});
rl.on("line", (line) => {
	const text = line.trim();
	if (text === "") return rl.prompt();
	if (text === "/quit") return void shutdown(0);
	// The steering doorbell only says the inbox changed; the bridge delivers
	// the messages themselves, so the line is never model input.
	if (text.startsWith(DOORBELL)) {
		void admitInbox();
		return rl.prompt();
	}
	void admitInbox().then(() =>
		root
			.submit({ type: "input", content: text, whenBusy: "steer" }, context)
			.catch((error) => log(`submit failed: ${error.message}`)),
	);
	rl.prompt();
});
rl.on("close", () => void shutdown(0));
rl.on("SIGINT", () => {
	if (running) void root.abort(context).then(() => log("interrupted"));
	else rl.prompt();
});
log(`pi-durable ${args.model} · store ${store}`);
