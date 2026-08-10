import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import {
	isBashToolResult,
	isToolCallEventType,
	type ExtensionAPI,
	type ToolResultEvent,
} from "@earendil-works/pi-coding-agent";

type BridgeInput = {
	event_type: "tool_call" | "tool_result" | "stop";
	cwd: string;
	event: unknown;
};

type PiStopReason = "pending" | "stop" | "length" | "toolUse" | "error" | "aborted";

type BridgeResponse =
	| { action: "allow" }
	| { action: "block"; reason?: string }
	| { action: "context"; messages?: string[] }
	| { action: "follow_up"; reasons: string[] };

function claudeStopReason(stopReason: PiStopReason | string): string {
	switch (stopReason) {
		case "pending": return "pending";
		case "stop": return "end_turn";
		case "length": return "end_turn";
		case "toolUse": return "tool_use";
		case "error": return "error";
		case "aborted": return "aborted";
		default: return "end_turn";
	}
}

function bridgePath(): string {
	return join(homedir(), ".local", "bin", "pi-claude-hook-bridge");
}

function isStringArray(value: unknown): value is string[] {
	return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function parseBridgeResponse(stdout: string): BridgeResponse {
	const parsed: unknown = JSON.parse(stdout || "{}");
	if (!parsed || typeof parsed !== "object" || !("action" in parsed)) {
		return { action: "allow" };
	}

	const response = parsed as Record<string, unknown>;
	if (response.action === "block") {
		return {
			action: "block",
			reason: typeof response.reason === "string" ? response.reason : undefined,
		};
	}
	if (response.action === "follow_up") {
		return { action: "follow_up", reasons: isStringArray(response.reasons) ? response.reasons : [] };
	}
	if (response.action === "context") {
		return {
			action: "context",
			messages: isStringArray(response.messages) ? response.messages : [],
		};
	}
	return { action: "allow" };
}

async function runBridge(input: BridgeInput): Promise<BridgeResponse> {
	const child = spawn(bridgePath(), [], {
		stdio: ["pipe", "pipe", "pipe"],
	});

	const stdoutChunks: Buffer[] = [];
	const stderrChunks: Buffer[] = [];
	child.stdout.on("data", (chunk: Buffer) => stdoutChunks.push(chunk));
	child.stderr.on("data", (chunk: Buffer) => stderrChunks.push(chunk));

	const exitCode = await new Promise<number | null>((resolve, reject) => {
		child.once("error", reject);
		child.once("close", resolve);
		child.stdin.end(JSON.stringify(input));
	});

	const stdout = Buffer.concat(stdoutChunks).toString("utf8").trim();
	if (exitCode !== 0) {
		const stderr = Buffer.concat(stderrChunks).toString("utf8").trim();
		return {
			action: "block",
			reason: `Pi Claude hook bridge exited ${exitCode}${stderr ? `: ${stderr}` : ""}`,
		};
	}

	try {
		return parseBridgeResponse(stdout);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return {
			action: "block",
			reason: `Pi Claude hook bridge returned invalid JSON: ${message}`,
		};
	}
}

function textContent(text: string): { type: "text"; text: string } {
	return { type: "text", text };
}

async function handleBashToolResult(event: ToolResultEvent, cwd: string) {
	if (!isBashToolResult(event)) {
		return undefined;
	}

	const response = await runBridge({
		event_type: "tool_result",
		cwd,
		event,
	});
	if (response.action !== "context" || !response.messages?.length) {
		return undefined;
	}

	return {
		content: [...event.content, ...response.messages.map(textContent)],
	};
}

const claudeInstructionsPath = join(homedir(), "CLAUDE.md");

function appendClaudeInstructions(event: {
	systemPrompt: string;
	systemPromptOptions: {
		contextFiles?: Array<{ path: string; content: string }>;
	};
}): { systemPrompt: string } | undefined {
	const contextFiles = event.systemPromptOptions.contextFiles ?? [];
	if (
		contextFiles.some((file) => file.path === claudeInstructionsPath) ||
		!existsSync(claudeInstructionsPath)
	) {
		return undefined;
	}

	let content: string;
	try {
		content = readFileSync(claudeInstructionsPath, "utf8");
	} catch {
		return undefined;
	}

	return {
		systemPrompt: `${event.systemPrompt}\n\n<project_context>\n\nProject-specific instructions and guidelines:\n\n<project_instructions path="${claudeInstructionsPath}">\n${content}\n</project_instructions>\n\n</project_context>\n`,
	};
}

export default function (pi: ExtensionAPI) {
	pi.on("resources_discover", (event) => ({
		skillPaths: [
			join(homedir(), ".claude", "skills"),
			join(event.cwd, ".claude", "skills"),
		],
	}));

	pi.on("tool_call", async (event, ctx) => {
		if (!isToolCallEventType("bash", event)) {
			return undefined;
		}

		const response = await runBridge({
			event_type: "tool_call",
			cwd: ctx.cwd,
			event,
		});
		if (response.action !== "block") {
			return undefined;
		}

		return {
			block: true,
			reason: response.reason ?? "Blocked by Claude-compatible Pi hook bridge",
		};
	});

	pi.on("before_agent_start", (event) => appendClaudeInstructions(event));

	pi.on("tool_result", async (event, ctx) => handleBashToolResult(event, ctx.cwd));

	pi.on("agent_end", async (event, ctx) => {
		const message = [...event.messages].reverse().find((candidate) => candidate.role === "assistant");
		if (!message) return undefined;
		const text = message.content.filter((block) => block.type === "text").map((block) => block.text).join("\n");
		const sessionId = ctx.sessionManager.getSessionId();
		let response: BridgeResponse;
		try {
			const stopReason = claudeStopReason(message.stopReason);
			response = await runBridge({
				event_type: "stop",
				cwd: ctx.cwd,
				event: { last_assistant_message: text, stop_reason: stopReason, cwd: ctx.cwd, working_directory: ctx.cwd, session_id: sessionId, conversation_id: sessionId, workspace_roots: [ctx.cwd] },
			});
		} catch (error) {
			const reason = error instanceof Error ? error.message : String(error);
			response = { action: "block", reason: `Pi Claude hook bridge failed: ${reason}` };
		}
		const reasons = response.action === "follow_up"
			? response.reasons
			: response.action === "block"
				? [response.reason ?? "Blocked by Claude-compatible Pi hook bridge"]
				: [];
		if (!reasons.length) return undefined;
		// Each agent_end callback gets exactly one follow-up; later turns must be checked again.
		await pi.sendUserMessage(`Address all Stop-hook feedback by continuing the prior task:\n${reasons.map((reason) => `- ${reason}`).join("\n")}`, { deliverAs: "followUp" });
		return undefined;
	});
}
