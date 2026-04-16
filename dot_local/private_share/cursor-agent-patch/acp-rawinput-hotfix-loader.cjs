"use strict";

const fs = require("node:fs");
const Module = require("node:module");

const isAcpCommand =
  process.argv.includes("acp") || process.env.CURSOR_ACP_HOTFIX_FORCE === "1";

if (!isAcpCommand) {
  return;
}

const BEFORE =
  "this.sentToolCalls.add(t.message.value.callId),yield this.sendToolCall({toolCallId:t.message.value.callId,title:n,kind:s,rawInput:this.extractToolCallInput(o),locations:this.extractToolCallLocations(o)})";
const AFTER =
  "const i=this.extractToolCallInput(o),r=this.extractToolCallLocations(o),a=!!i&&Object.values(i).some((e=>void 0!==e));(a||r)&&(this.sentToolCalls.add(t.message.value.callId),yield this.sendToolCall({toolCallId:t.message.value.callId,title:n,kind:s,rawInput:i,locations:r}))";
const REQUIRED_MARKER = "./src/acp/agent-session.ts";
const originalLoader = Module._extensions[".js"];

Module._extensions[".js"] = function patchedJsLoader(module, filename) {
  let source;
  try {
    source = fs.readFileSync(filename, "utf8");
  } catch {
    return originalLoader(module, filename);
  }

  const matchesAcpBundle =
    source.includes(REQUIRED_MARKER) && source.includes("sentToolCalls");
  if (!matchesAcpBundle || !source.includes(BEFORE)) {
    return originalLoader(module, filename);
  }

  const patched = source.replace(BEFORE, AFTER);
  if (process.env.CURSOR_AGENT_PATCH_DEBUG === "1") {
    process.stderr.write(
      `[agent-patched] applied ACP rawInput patch to ${filename}\n`,
    );
  }
  module._compile(patched, filename);
};
