import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

import {
	isBashToolResult,
	isToolCallEventType,
	type ExtensionAPI,
	type MessageEndEvent,
	type ToolResultEvent,
} from "@earendil-works/pi-coding-agent";

type BridgeInput = {
	event_type: "tool_call" | "tool_result" | "message_end";
	cwd: string;
	event: unknown;
};

type BridgeResponse =
	| { action: "allow" }
	| { action: "block"; reason?: string }
	| { action: "context"; messages?: string[] }
	| { action: "stop_stub"; reason: string };

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
	if (response.action === "context") {
		return {
			action: "context",
			messages: isStringArray(response.messages) ? response.messages : [],
		};
	}
	if (response.action === "stop_stub") {
		return {
			action: "stop_stub",
			reason: typeof response.reason === "string" ? response.reason : "",
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

async function maybeRunStopStub(event: MessageEndEvent, cwd: string): Promise<void> {
	if (process.env.PI_CLAUDE_HOOK_BRIDGE_CHECK_STOP !== "1") {
		return;
	}

	const response = await runBridge({
		event_type: "message_end",
		cwd,
		event,
	});
	if (response.action === "stop_stub") {
		process.stderr.write(`Pi Claude Stop hook stub: ${response.reason}\n`);
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("resources_discover", () => ({
		skillPaths: [join(homedir(), ".claude", "skills")],
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

	pi.on("tool_result", async (event, ctx) => handleBashToolResult(event, ctx.cwd));

	pi.on("message_end", async (event, ctx) => {
		await maybeRunStopStub(event, ctx.cwd);
	});
}
