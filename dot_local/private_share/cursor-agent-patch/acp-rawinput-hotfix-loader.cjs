"use strict";

const fs = require("node:fs");
const Module = require("node:module");

const isAcpCommand =
  process.argv.includes("acp") || process.env.CURSOR_ACP_HOTFIX_FORCE === "1";
const EXPECTED_SESSION_VERSION =
  process.env.CURSOR_AGENT_PATCH_SESSION_VERSION || "2026.04.16-2d20146";

if (!isAcpCommand) {
  return;
}
debugLog("[agent-patched] ACP loader active");

const BEFORE =
  "this.sentToolCalls.add(t.message.value.callId),yield this.sendToolCall({toolCallId:t.message.value.callId,title:n,kind:s,rawInput:this.extractToolCallInput(o),locations:this.extractToolCallLocations(o)})";
const AFTER =
  "const i=this.extractToolCallInput(o),r=this.extractToolCallLocations(o),a=!!i&&Object.values(i).some((e=>void 0!==e));(a||r)&&(this.sentToolCalls.add(t.message.value.callId),yield this.sendToolCall({toolCallId:t.message.value.callId,title:n,kind:s,rawInput:i,locations:r}))";
const REQUIRED_MARKER = "./src/acp/agent-session.ts";
const STOP_GATE_RE =
  /e\.hookExecutor&&e\.hooksConfig&&[\s\S]*?&&e\.hookExecutor\.executeHookForStep\(f\._E\.stop,/g;
const STOP_GATE_REPLACEMENT =
  "e.hookExecutor&&e.hooksConfig&&((e.hooksConfig.userHooks?.hooks?.stop?.length)||(e.hooksConfig.projectHooks?.hooks?.stop?.length)||(e.hooksConfig.claudeUserHooks?.hooks?.stop?.length)||(e.hooksConfig.claudeProjectHooks?.hooks?.stop?.length)||(e.hooksConfig.claudeProjectLocalHooks?.hooks?.stop?.length))&&e.hookExecutor.executeHookForStep(f._E.stop,";
const BEFORE_SUBMIT_GATE_RE =
  /e\.hookExecutor&&e\.hooksConfig&&[\s\S]*?&&e\.hookExecutor\.executeHookForStep\(f\._E\.beforeSubmitPrompt,/g;
const BEFORE_SUBMIT_GATE_REPLACEMENT =
  "e.hookExecutor&&e.hooksConfig&&((e.hooksConfig.userHooks?.hooks?.beforeSubmitPrompt?.length)||(e.hooksConfig.projectHooks?.hooks?.beforeSubmitPrompt?.length)||(e.hooksConfig.claudeUserHooks?.hooks?.beforeSubmitPrompt?.length)||(e.hooksConfig.claudeProjectHooks?.hooks?.beforeSubmitPrompt?.length)||(e.hooksConfig.claudeProjectLocalHooks?.hooks?.beforeSubmitPrompt?.length))&&e.hookExecutor.executeHookForStep(f._E.beforeSubmitPrompt,";
const CLAUDE_BRIDGE_BEFORE =
  "return this.dedupeClaudeHooksAgainstCursorHooks(t),t";
const CLAUDE_BRIDGE_AFTER =
  'return this.dedupeClaudeHooksAgainstCursorHooks(t),function(e){const o=["stop","beforeSubmitPrompt"],t=(e,t)=>{var o,n;const a=null===(n=null===(o=e)||void 0===o?void 0:o.hooks)||void 0===n?void 0:n[t];return Array.isArray(a)?a:[]},r=(e,o)=>{e.hooks||(e.hooks={});const t=e.hooks[o];return Array.isArray(t)?t:(e.hooks[o]=[],e.hooks[o])},n=e=>e&&"object"==typeof e?e:{hooks:{}};e.userHooks=n(e.userHooks),e.projectHooks=n(e.projectHooks);for(const n of o){r(e.userHooks,n).push(...t(e.claudeUserHooks,n));const o=r(e.projectHooks,n);o.push(...t(e.claudeProjectHooks,n),...t(e.claudeProjectLocalHooks,n))}}(t),t';
const MODEL_REQUEST_FORMAT_BEFORE =
  "function s(e){return o()&&void 0!==e.requestedModel?{modelDetails:void 0,requestedModel:e.requestedModel}:{modelDetails:e.modelDetails,requestedModel:void 0}}";
const MODEL_REQUEST_FORMAT_AFTER =
  "function s(e){return void 0!==e.requestedModel?{modelDetails:void 0,requestedModel:e.requestedModel}:{modelDetails:e.modelDetails,requestedModel:void 0}}";
const originalLoader = Module._extensions[".js"];
const seenChunkFiles = new Set();
const DEBUG_LOG_FILE = "/tmp/agent-patched-loader.log";
let didVersionCheck = false;

function getVersionFromFilename(filename) {
  const match = filename.match(/\/cursor-agent\/versions\/([^/]+)\//);
  return match ? match[1] : null;
}

function debugLog(message) {
  if (process.env.CURSOR_AGENT_PATCH_DEBUG !== "1") {
    return;
  }
  process.stderr.write(message + "\n");
  try {
    fs.appendFileSync(DEBUG_LOG_FILE, message + "\n", "utf8");
  } catch {
    // Best effort only.
  }
}

Module._extensions[".js"] = function patchedJsLoader(module, filename) {
  if (
    process.env.CURSOR_AGENT_PATCH_DEBUG === "1" &&
    (filename.endsWith(".index.js") || filename.endsWith("/index.js"))
  ) {
    if (!seenChunkFiles.has(filename)) {
      seenChunkFiles.add(filename);
      debugLog(`[agent-patched] loading chunk ${filename}`);
    }
  }
  let source;
  try {
    source = fs.readFileSync(filename, "utf8");
  } catch {
    return originalLoader(module, filename);
  }

  if (!didVersionCheck && filename.endsWith("/index.js")) {
    didVersionCheck = true;
    const runtimeVersion = getVersionFromFilename(filename);
    if (runtimeVersion && runtimeVersion !== EXPECTED_SESSION_VERSION) {
      const message = `[agent-patched] session version mismatch: expected ${EXPECTED_SESSION_VERSION}, runtime ${runtimeVersion}`;
      process.stderr.write(message + "\n");
      try {
        fs.appendFileSync(DEBUG_LOG_FILE, message + "\n", "utf8");
      } catch {
        // Best effort only.
      }
      process.exit(1);
    }
  }

  let patched = source;
  let changed = false;
  let rawInputPatched = false;
  let stopGatePatchCount = 0;
  let beforeSubmitPatchCount = 0;
  let claudeBridgePatched = false;
  let modelRequestFormatPatched = false;

  const matchesAcpBundle =
    source.includes(REQUIRED_MARKER) && source.includes("sentToolCalls");
  if (matchesAcpBundle && patched.includes(BEFORE)) {
    patched = patched.replace(BEFORE, AFTER);
    rawInputPatched = true;
    changed = true;
  }

  if (patched.includes("executeHookForStep(f._E.stop")) {
    patched = patched.replace(STOP_GATE_RE, (match) => {
      if (
        match.includes("claudeUserHooks?.hooks?.stop?.length") &&
        match.includes("claudeProjectHooks?.hooks?.stop?.length") &&
        match.includes("claudeProjectLocalHooks?.hooks?.stop?.length")
      ) {
        return match;
      }
      stopGatePatchCount += 1;
      changed = true;
      return STOP_GATE_REPLACEMENT;
    });
  }

  if (patched.includes("executeHookForStep(f._E.beforeSubmitPrompt")) {
    patched = patched.replace(BEFORE_SUBMIT_GATE_RE, (match) => {
      if (
        match.includes("claudeUserHooks?.hooks?.beforeSubmitPrompt?.length") &&
        match.includes("claudeProjectHooks?.hooks?.beforeSubmitPrompt?.length") &&
        match.includes("claudeProjectLocalHooks?.hooks?.beforeSubmitPrompt?.length")
      ) {
        return match;
      }
      beforeSubmitPatchCount += 1;
      changed = true;
      return BEFORE_SUBMIT_GATE_REPLACEMENT;
    });
  }

  if (patched.includes(CLAUDE_BRIDGE_BEFORE)) {
    patched = patched.replace(CLAUDE_BRIDGE_BEFORE, CLAUDE_BRIDGE_AFTER);
    changed = true;
    claudeBridgePatched = true;
  }

  if (
    patched.includes("./src/model-request-format.ts") &&
    patched.includes(MODEL_REQUEST_FORMAT_BEFORE)
  ) {
    patched = patched.replace(
      MODEL_REQUEST_FORMAT_BEFORE,
      MODEL_REQUEST_FORMAT_AFTER,
    );
    changed = true;
    modelRequestFormatPatched = true;
  }

  if (!changed) {
    return originalLoader(module, filename);
  }
  debugLog(
    "[agent-patched] applied ACP patches to " +
      filename +
      ` (rawInput=${rawInputPatched ? "yes" : "no"}, stopGate=${stopGatePatchCount}, beforeSubmit=${beforeSubmitPatchCount}, claudeBridge=${claudeBridgePatched ? "yes" : "no"}, modelRequestFormat=${modelRequestFormatPatched ? "yes" : "no"})`,
  );
  module._compile(patched, filename);
};
