/**
 * Anthropic Provider with Disabled Body Timeout
 * 
 * Simple provider for local Anthropic-compatible servers (vLLM, LM Studio)
 * with disabled body timeout to prevent UND_ERR_BODY_TIMEOUT errors.
 */

import Anthropic from "@anthropic-ai/sdk";
import type { MessageCreateParamsStreaming } from "@anthropic-ai/sdk/resources/messages.js";
import { Agent } from "undici";
import {
	type AssistantMessage,
	type AssistantMessageEventStream,
	type Context,
	calculateCost,
	createAssistantMessageEventStream,
	type Message,
	type Model,
	type SimpleStreamOptions,
	type StopReason,
	type Tool,
} from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

// Custom fetch with disabled body timeout
const dispatcher = new Agent({ bodyTimeout: 0, headersTimeout: 0 });
const fetchWithNoBodyTimeout = (input: RequestInfo | URL, init?: RequestInit) => {
	return fetch(input, { ...init, dispatcher } as any);
};

function mapStopReason(reason: string): StopReason {
	switch (reason) {
		case "end_turn":
		case "pause_turn":
		case "stop_sequence":
			return "stop";
		case "max_tokens":
			return "length";
		case "tool_use":
			return "toolUse";
		default:
			return "error";
	}
}

function streamAnthropicNoTimeout(
	model: Model,
	context: Context,
	options?: SimpleStreamOptions,
): AssistantMessageEventStream {
	const stream = createAssistantMessageEventStream();

	(async () => {
		const output: AssistantMessage = {
			role: "assistant",
			content: [],
			api: model.api,
			provider: model.provider,
			model: model.id,
			usage: {
				input: 0,
				output: 0,
				cacheRead: 0,
				cacheWrite: 0,
				totalTokens: 0,
				cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
			},
			stopReason: "stop",
			timestamp: Date.now(),
		};

		try {
			const client = new Anthropic({
				baseURL: model.baseUrl,
				apiKey: options?.apiKey || "not-needed",
				dangerouslyAllowBrowser: true,
				fetch: fetchWithNoBodyTimeout,
			});

			const params: MessageCreateParamsStreaming = {
				model: model.id,
				messages: context.messages.map((msg) => {
					if (msg.role === "user") {
						return {
							role: "user",
							content: typeof msg.content === "string"
								? msg.content
								: msg.content.map((c) => c.type === "text" ? { type: "text", text: c.text } : c),
						};
					}
					if (msg.role === "assistant") {
						return {
							role: "assistant",
							content: msg.content.map((c) => {
								if (c.type === "text") return { type: "text", text: c.text };
								if (c.type === "toolCall") return { type: "tool_use", id: c.id, name: c.name, input: c.arguments };
								return c;
							}),
						};
					}
					if (msg.role === "toolResult") {
						return {
							role: "user",
							content: [{
								type: "tool_result",
								tool_use_id: msg.toolCallId,
								content: msg.content.map((c) => c.type === "text" ? { type: "text", text: c.text } : c),
								is_error: msg.isError,
							}],
						};
					}
					return msg as any;
				}),
				max_tokens: options?.maxTokens || Math.floor(model.maxTokens / 3),
				stream: true,
			};

			if (context.systemPrompt) {
				(params as any).system = context.systemPrompt;
			}

			const anthropicStream = await client.messages.stream(params, { signal: options?.signal });

			stream.push({ type: "start", partial: output });

			for await (const event of anthropicStream) {
				if (event.type === "message_start") {
					output.usage.input = event.message.usage.input_tokens || 0;
					output.usage.output = event.message.usage.output_tokens || 0;
					output.usage.cacheRead = (event.message.usage as any).cache_read_input_tokens || 0;
					output.usage.cacheWrite = (event.message.usage as any).cache_creation_input_tokens || 0;
					output.usage.totalTokens = output.usage.input + output.usage.output + output.usage.cacheRead + output.usage.cacheWrite;
					calculateCost(model, output.usage);
				} else if (event.type === "content_block_start") {
					if (event.content_block.type === "text") {
						output.content.push({ type: "text", text: "" });
						stream.push({ type: "text_start", contentIndex: output.content.length - 1, partial: output });
					} else if (event.content_block.type === "tool_use") {
						output.content.push({ type: "toolCall", id: event.content_block.id, name: event.content_block.name, arguments: {} });
						stream.push({ type: "toolcall_start", contentIndex: output.content.length - 1, partial: output });
					}
				} else if (event.type === "content_block_delta") {
					const block = output.content[output.content.length - 1];
					if (event.delta.type === "text_delta" && block?.type === "text") {
						block.text += event.delta.text;
						stream.push({ type: "text_delta", contentIndex: output.content.length - 1, delta: event.delta.text, partial: output });
					} else if (event.delta.type === "input_json_delta" && block?.type === "toolCall") {
						const toolBlock = block as any;
						toolBlock.partialJson = (toolBlock.partialJson || "") + event.delta.partial_json;
						try {
							block.arguments = JSON.parse(toolBlock.partialJson);
						} catch {}
						stream.push({ type: "toolcall_delta", contentIndex: output.content.length - 1, delta: event.delta.partial_json, partial: output });
					}
				} else if (event.type === "content_block_stop") {
					const block = output.content[output.content.length - 1];
					if (block?.type === "text") {
						stream.push({ type: "text_end", contentIndex: output.content.length - 1, content: block.text, partial: output });
					} else if (block?.type === "toolCall") {
						stream.push({ type: "toolcall_end", contentIndex: output.content.length - 1, toolCall: block, partial: output });
					}
				} else if (event.type === "message_delta") {
					if ((event.delta as any).stop_reason) {
						output.stopReason = mapStopReason((event.delta as any).stop_reason);
					}
					output.usage.input = (event.usage as any).input_tokens || 0;
					output.usage.output = (event.usage as any).output_tokens || 0;
					output.usage.cacheRead = (event.usage as any).cache_read_input_tokens || 0;
					output.usage.cacheWrite = (event.usage as any).cache_creation_input_tokens || 0;
					output.usage.totalTokens = output.usage.input + output.usage.output + output.usage.cacheRead + output.usage.cacheWrite;
					calculateCost(model, output.usage);
				}
			}

			stream.push({ type: "done", reason: output.stopReason, message: output });
			stream.end();
		} catch (error) {
			output.stopReason = options?.signal?.aborted ? "aborted" : "error";
			output.errorMessage = error instanceof Error ? error.message : JSON.stringify(error);
			stream.push({ type: "error", reason: output.stopReason, error: output });
			stream.end();
		}
	})();

	return stream;
}

export default function (pi: ExtensionAPI) {
	// Register provider capability - models added via LLM_ENDPOINT or models.json
	pi.registerProvider("anthropic-no-timeout", {
		baseUrl: "",  // Set per-model via models.json
		apiKey: "not-needed",
		api: "anthropic",
		models: [],  // Empty - models added via LLM_ENDPOINT or models.json
		streamSimple: streamAnthropicNoTimeout,
	});
}
