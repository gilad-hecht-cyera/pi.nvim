import { complete } from "@earendil-works/pi-ai/compat";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { registerAutoSessionName } from "./auto-session-name-core.mjs";

async function generateTitle(conversation: string, ctx: ExtensionContext): Promise<string> {
	if (!ctx.model) throw new Error("No model selected");
	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model);
	if (!auth.ok) throw new Error(auth.error);
	if (!auth.apiKey) throw new Error(`No API key for ${ctx.model.provider}/${ctx.model.id}`);

	const response = await complete(
		{ ...ctx.model, maxTokens: 256 },
		{
			messages: [
				{
					role: "user",
					content: [
						{
							type: "text",
							text: [
								"Create a concise display name for this coding session.",
								"Respond with only the title, without quotes or ending punctuation.",
								"Use at most 12 words and ideally 5-6 words.",
								"",
								"<conversation>",
								conversation,
								"</conversation>",
							].join("\n"),
						},
					],
					timestamp: Date.now(),
				},
			],
		},
		{ apiKey: auth.apiKey, headers: auth.headers, env: auth.env },
	);

	return response.content
		.filter((part): part is { type: "text"; text: string } => part.type === "text")
		.map((part) => part.text)
		.join("\n");
}

export default function (pi: ExtensionAPI) {
	registerAutoSessionName(pi, generateTitle);
}
