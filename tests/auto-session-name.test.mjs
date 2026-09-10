import assert from "node:assert/strict";
import test from "node:test";
import {
	buildConversationText,
	normalizeSessionTitle,
	registerAutoSessionName,
} from "../extensions/auto-session-name-core.mjs";

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

test("manual autoname generates and applies a name", async () => {
	const state = harness({ entries: firstExchange });
	registerAutoSessionName(state.pi, async () => "Fix session naming");

	await state.commands.get("pi-nvim-autoname").handler("", state.ctx);

	assert.deepEqual(state.names, ["Fix session naming"]);
	assert.deepEqual(state.notifications, [["Session name set: Fix session naming", "info"]]);
});
