import { mock } from "node:test";

export const complete = mock.fn(async () => ({
	content: [
		{ type: "thinking", thinking: "Choose a concise title" },
		{ type: "text", text: "Fix session" },
		{ type: "text", text: "naming" },
	],
}));
