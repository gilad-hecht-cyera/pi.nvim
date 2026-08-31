const MAX_CONVERSATION_LENGTH = 12000;

function contentText(content) {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.filter((part) => part && typeof part === "object" && part.type === "text" && typeof part.text === "string")
		.map((part) => part.text)
		.join("\n");
}

export function normalizeSessionTitle(value) {
	let title = String(value ?? "").trim();
	title = title.replace(/^```[\w-]*\s*/, "").replace(/\s*```$/, "");
	title = title.replace(/^#+\s*/, "").replace(/^["'`]+/, "").replace(/["'`.]+$/, "");
	title = title.replace(/\s+/g, " ").trim();
	return title.split(" ").slice(0, 12).join(" ");
}

export function buildConversationText(entries) {
	const sections = [];
	for (const entry of entries ?? []) {
		if (entry?.type !== "message") continue;
		const role = entry.message?.role;
		if (role !== "user" && role !== "assistant") continue;
		const text = contentText(entry.message.content).trim();
		if (text) sections.push(`${role === "user" ? "User" : "Assistant"}: ${text}`);
	}
	return sections.join("\n\n").slice(0, MAX_CONVERSATION_LENGTH);
}

function assistantMessageCount(entries) {
	return (entries ?? []).filter((entry) => entry?.type === "message" && entry.message?.role === "assistant").length;
}

export function registerAutoSessionName(pi, generateTitle) {
	let eligibleForAutomaticName = false;
	let naming = false;

	async function nameSession(ctx, notify) {
		if (naming) return undefined;
		const conversation = buildConversationText(ctx.sessionManager.getBranch());
		if (!conversation) {
			if (notify && ctx.hasUI) ctx.ui.notify("No conversation found to name", "warning");
			return undefined;
		}

		naming = true;
		try {
			const title = normalizeSessionTitle(await generateTitle(conversation, ctx));
			if (!title) {
				if (notify && ctx.hasUI) ctx.ui.notify("Pi did not suggest a session name", "warning");
				return undefined;
			}
			pi.setSessionName(title);
			if (notify && ctx.hasUI) ctx.ui.notify(`Session name set: ${title}`, "info");
			return title;
		} catch (error) {
			if (notify && ctx.hasUI) ctx.ui.notify(`Failed to name session: ${String(error)}`, "warning");
			return undefined;
		} finally {
			naming = false;
		}
	}

	pi.on("session_start", (_event, ctx) => {
		eligibleForAutomaticName = !pi.getSessionName() && assistantMessageCount(ctx.sessionManager.getBranch()) === 0;
	});

	pi.on("agent_settled", async (_event, ctx) => {
		if (!eligibleForAutomaticName) return;
		eligibleForAutomaticName = false;
		if (pi.getSessionName()) return;
		await nameSession(ctx, false);
	});

	pi.registerCommand("pi-nvim-autoname", {
		description: "Generate and apply a concise name for the current session",
		handler: async (_args, ctx) => {
			await nameSession(ctx, true);
		},
	});
}
