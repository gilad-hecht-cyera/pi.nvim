import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test, { beforeEach, mock } from "node:test";
import { complete } from "./fixtures/pi-ai-compat.mjs";
import {
	buildConversationText,
	normalizeSessionTitle,
	registerAutoSessionName,
} from "../extensions/auto-session-name-core.mjs";

const hooks = registerHooks({
	resolve(specifier, context, nextResolve) {
		if (specifier === "@earendil-works/pi-ai/compat") {
			return { url: new URL("./fixtures/pi-ai-compat.mjs", import.meta.url).href, shortCircuit: true };
		}
		return nextResolve(specifier, context);
	},
});
let autoSessionName;
try {
	({ default: autoSessionName } = await import("../extensions/auto-session-name.ts"));
} finally {
	hooks.deregister();
}

beforeEach(() => complete.mock.resetCalls());

function harness({ name, entries = [] } = {}) {
	const handlers = new Map();
	const commands = new Map();
	const names = [];
	const notifications = [];
	let currentName = name;
	const pi = {
		on(event, handler) {
			handlers.set(event, handler);
		},
		registerCommand(command, definition) {
			commands.set(command, definition);
		},
		getSessionName() {
			return currentName;
		},
		setSessionName(nextName) {
			currentName = nextName;
			names.push(nextName);
		},
	};
	const ctx = {
		hasUI: true,
		sessionManager: { getBranch: () => entries },
		ui: { notify: (...args) => notifications.push(args) },
	};
	return { pi, ctx, handlers, commands, names, notifications };
}

const firstExchange = [
	{ type: "message", message: { role: "user", content: [{ type: "text", text: "Fix session naming" }] } },
	{ type: "message", message: { role: "assistant", content: [{ type: "text", text: "I fixed it." }] } },
];

test("normalizes model output into a concise title", () => {
	assert.equal(
		normalizeSessionTitle('```text\n# "Automatically name coding sessions after their first completed agent run today."\n```'),
		"Automatically name coding sessions after their first completed agent run today",
	);
});

test("builds conversation text from user and assistant messages", () => {
	assert.equal(buildConversationText(firstExchange), "User: Fix session naming\n\nAssistant: I fixed it.");
});

test("names a new unnamed session after its first settled run only", async () => {
	const state = harness({ entries: [] });
	let calls = 0;
	registerAutoSessionName(state.pi, async () => {
		calls += 1;
		return "Automatic session naming";
	});

	await state.handlers.get("session_start")({}, state.ctx);
	state.ctx.sessionManager.getBranch = () => firstExchange;
	await state.handlers.get("agent_settled")({}, state.ctx);
	await state.handlers.get("agent_settled")({}, state.ctx);

	assert.equal(calls, 1);
	assert.deepEqual(state.names, ["Automatic session naming"]);
});

test("does not automatically overwrite a name or name a resumed conversation", async () => {
	for (const initial of [{ name: "Manual name", entries: [] }, { entries: firstExchange }]) {
		const state = harness(initial);
		let calls = 0;
		registerAutoSessionName(state.pi, async () => {
			calls += 1;
			return "Replacement";
		});
		await state.handlers.get("session_start")({}, state.ctx);
		await state.handlers.get("agent_settled")({}, state.ctx);
		assert.equal(calls, 0);
		assert.deepEqual(state.names, []);
	}
});

function completionHarness(auth, model = { provider: "amazon-bedrock", id: "global.openai.gpt-6-astra" }) {
	const state = harness({ entries: firstExchange });
	state.ctx.model = model;
	state.ctx.modelRegistry = { getApiKeyAndHeaders: mock.fn(async () => auth) };
	autoSessionName(state.pi);
	return state;
}

async function runAutoname(state) {
	await state.commands.get("pi-nvim-autoname").handler("", state.ctx);
	assert.equal(state.ctx.modelRegistry.getApiKeyAndHeaders.mock.callCount(), 1);
	assert.deepEqual(state.ctx.modelRegistry.getApiKeyAndHeaders.mock.calls[0].arguments, [state.ctx.model]);
}

test("actual title generation completes after successful auth without an API key", async () => {
	const state = completionHarness({ ok: true });

	await runAutoname(state);

	assert.equal(complete.mock.callCount(), 1);
	const [model, context, options] = complete.mock.calls[0].arguments;
	assert.deepEqual(model, { ...state.ctx.model, maxTokens: 256 });
	assert.equal(options.apiKey, undefined);
	assert.equal(context.messages[0].role, "user");
	assert.ok(context.messages[0].content[0].text.includes(buildConversationText(firstExchange)));
	assert.deepEqual(state.names, ["Fix session naming"]);
	assert.deepEqual(state.notifications, [["Session name set: Fix session naming", "info"]]);
});

test("actual title generation forwards resolved environment and headers without an API key", async () => {
	const env = { AWS_PROFILE: "test-profile", AWS_REGION: "us-west-2" };
	const headers = { "x-session-naming": "test" };
	const state = completionHarness({ ok: true, env, headers });

	await runAutoname(state);

	assert.equal(complete.mock.callCount(), 1);
	const options = complete.mock.calls[0].arguments[2];
	assert.deepEqual(options, { apiKey: undefined, env, headers });
	assert.strictEqual(options.env, env);
	assert.strictEqual(options.headers, headers);
	assert.deepEqual(state.names, ["Fix session naming"]);
});

test("actual title generation still forwards API-key authentication", async () => {
	const auth = {
		ok: true,
		apiKey: "test-api-key",
		headers: { "x-request-source": "test" },
		env: { HTTPS_PROXY: "http://localhost:8080" },
	};
	const state = completionHarness(auth, { provider: "anthropic", id: "claude-sonnet-4-5" });

	await runAutoname(state);

	assert.equal(complete.mock.callCount(), 1);
	assert.deepEqual(complete.mock.calls[0].arguments[2], {
		apiKey: auth.apiKey,
		headers: auth.headers,
		env: auth.env,
	});
	assert.deepEqual(state.names, ["Fix session naming"]);
});

test("actual title generation reports auth failures without calling completion", async () => {
	const state = completionHarness({ ok: false, error: "Unable to resolve credentials for profile test-profile" });

	await runAutoname(state);

	assert.equal(complete.mock.callCount(), 0);
	assert.deepEqual(state.names, []);
	assert.deepEqual(state.notifications, [
		["Failed to name session: Error: Unable to resolve credentials for profile test-profile", "warning"],
	]);
});

test("manual autoname generates and applies a name", async () => {
	const state = harness({ entries: firstExchange });
	registerAutoSessionName(state.pi, async () => "Fix session naming");

	await state.commands.get("pi-nvim-autoname").handler("", state.ctx);

	assert.deepEqual(state.names, ["Fix session naming"]);
	assert.deepEqual(state.notifications, [["Session name set: Fix session naming", "info"]]);
});
