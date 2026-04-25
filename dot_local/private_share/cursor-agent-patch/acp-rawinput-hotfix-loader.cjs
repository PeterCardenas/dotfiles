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
const TASK_OUTPUT_BEFORE =
  'case"taskToolCall":{const e=null===(w=b.value.result)||void 0===w?void 0:w.result;return"success"===(null==e?void 0:e.case)?{durationMs:void 0!==e.value.durationMs?Number(e.value.durationMs):void 0,isBackground:e.value.isBackground}:"error"===(null==e?void 0:e.case)?{error:e.value.error}:void 0}';
const TASK_OUTPUT_AFTER =
  'case"taskToolCall":{const e=null===(w=b.value.result)||void 0===w?void 0:w.result;return"success"===(null==e?void 0:e.case)?{durationMs:void 0!==e.value.durationMs?Number(e.value.durationMs):void 0,isBackground:e.value.isBackground,agentId:e.value.agentId,finalMessage:void 0!==e.value.finalMessage?e.value.finalMessage:function(e){try{const t=JSON.parse(JSON.stringify(e)),n=null==t?void 0:t.conversationSteps;if(!Array.isArray(n))return;for(let e=n.length-1;e>=0;e--){const t=n[e],o=null==t?void 0:t.assistantMessage,s=null==o?void 0:o.text;if("string"==typeof s&&s.length>0)return s}}catch(e){}}(e.value),toolCallCount:void 0!==e.value.toolCallCount?Number(e.value.toolCallCount):void 0,backgroundReason:e.value.backgroundReason,transcriptPath:e.value.transcriptPath,debugTaskResult:"1"===process.env.CURSOR_AGENT_PATCH_DEBUG?e.value:void 0}:"error"===(null==e?void 0:e.case)?{error:e.value.error,agentId:e.value.agentId,debugTaskResult:"1"===process.env.CURSOR_AGENT_PATCH_DEBUG?e.value:void 0}:void 0}';
const TASK_NOTIFICATION_BEFORE =
  'case"taskToolCall":{const t=l.value.args,o=null===(n=l.value.result)||void 0===n?void 0:n.result,r="success"===(null==o?void 0:o.case)?o.value.durationMs:void 0,a=void 0!==r?Number(r):void 0,d={toolCallId:e,description:null!==(s=null==t?void 0:t.description)&&void 0!==s?s:"",prompt:null!==(i=null==t?void 0:t.prompt)&&void 0!==i?i:"",subagentType:this.mapSubagentType(null==t?void 0:t.subagentType),model:null==t?void 0:t.model,agentId:null==t?void 0:t.agentId,durationMs:a};this.sendNonBlockingExtensionNotification(F.b8,d);break}';
const TASK_NOTIFICATION_AFTER =
  'case"taskToolCall":{const t=l.value.args,o=null===(n=l.value.result)||void 0===n?void 0:n.result,r="success"===(null==o?void 0:o.case)?o.value.durationMs:void 0,a=void 0!==r?Number(r):void 0,d="success"===(null==o?void 0:o.case)?o.value:void 0,c={toolCallId:e,description:null!==(s=null==t?void 0:t.description)&&void 0!==s?s:"",prompt:null!==(i=null==t?void 0:t.prompt)&&void 0!==i?i:"",subagentType:this.mapSubagentType(null==t?void 0:t.subagentType),model:null==t?void 0:t.model,agentId:null==t?void 0:t.agentId,durationMs:a,finalMessage:void 0!==(null==d?void 0:d.finalMessage)?d.finalMessage:function(e){try{const t=JSON.parse(JSON.stringify(e)),n=null==t?void 0:t.conversationSteps;if(!Array.isArray(n))return;for(let e=n.length-1;e>=0;e--){const t=n[e],o=null==t?void 0:t.assistantMessage,s=null==o?void 0:o.text;if("string"==typeof s&&s.length>0)return s}}catch(e){}}(d),toolCallCount:void 0!==(null==d?void 0:d.toolCallCount)?Number(d.toolCallCount):void 0,backgroundReason:null==d?void 0:d.backgroundReason,transcriptPath:null==d?void 0:d.transcriptPath,debugTaskResult:"1"===process.env.CURSOR_AGENT_PATCH_DEBUG?d:void 0};this.sendNonBlockingExtensionNotification(F.b8,c);break}';
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
  'function s(e){const t=e.requestedModel,n=t&&t.modelId;return void 0!==t&&("gpt-5.4"===n||"gpt-5.5"===n)?{modelDetails:void 0,requestedModel:t}:{modelDetails:e.modelDetails,requestedModel:void 0}}';
const ACP_SESSION_CTOR_BEFORE =
  "constructor(e,t,o,n,s,i,r){this.lastRequestId=null,this.sentToolCalls=new Set,this.pendingAutoNamePromise=null,this.connection=e,this.sessionId=t,this.pendingPromptCancel=null,this.sharedServices=o,this.ctx=n,this.agentStore=s,this.resources=i,this.currentModel=r,this.createPlanProgressPresenter";
const ACP_SESSION_CTOR_AFTER =
  'constructor(e,t,o,n,s,i,r,a){this.lastRequestId=null,this.sentToolCalls=new Set,this.pendingAutoNamePromise=null,this.connection=e,this.sessionId=t,this.pendingPromptCancel=null,this.sharedServices=o,this.ctx=n,this.agentStore=s,this.resources=i,this.currentModel=r,this.hookExecutor=a,this._lastAssistantMessage="",this.createPlanProgressPresenter';
const ACP_SESSION_NEW_BEFORE =
  "{resources:d}=yield(0,m.Y)(this.ctx,this.connection,this.sharedServices,r,this.options,l),u=yield this.sharedServices.modelManager.awaitCurrentModel(),v=new p.m(this.connection,o,this.sharedServices,this.ctx,r,d,u),";
const ACP_SESSION_NEW_AFTER =
  "{resources:d,hookExecutor:c}=yield(0,m.Y)(this.ctx,this.connection,this.sharedServices,r,this.options,l),u=yield this.sharedServices.modelManager.awaitCurrentModel(),v=new p.m(this.connection,o,this.sharedServices,this.ctx,r,d,u,c),";
const ACP_SESSION_LOAD_BEFORE =
  "{resources:d}=yield(0,m.Y)(this.ctx,this.connection,this.sharedServices,r,this.options,l),u=yield this.sharedServices.modelManager.awaitCurrentModel(),v=new p.m(this.connection,t,this.sharedServices,this.ctx,r,d,u),";
const ACP_SESSION_LOAD_AFTER =
  "{resources:d,hookExecutor:c}=yield(0,m.Y)(this.ctx,this.connection,this.sharedServices,r,this.options,l),u=yield this.sharedServices.modelManager.awaitCurrentModel(),v=new p.m(this.connection,t,this.sharedServices,this.ctx,r,d,u,c),";
const ACP_SEND_AGENT_CHUNK_BEFORE =
  'sendAgentMessageChunk(e){return $(this,void 0,void 0,(function*(){yield this.sendSessionUpdate({sessionUpdate:"agent_message_chunk",content:{type:"text",text:e}})}))}';
const ACP_SEND_AGENT_CHUNK_AFTER =
  'sendAgentMessageChunk(e){return $(this,void 0,void 0,(function*(){this._lastAssistantMessage=(this._lastAssistantMessage||"")+e,yield this.sendSessionUpdate({sessionUpdate:"agent_message_chunk",content:{type:"text",text:e}})}))}';
const ACP_HANDLE_PROMPT_BEFORE =
  'handlePrompt(e){return $(this,void 0,void 0,(function*(){var t;null===(t=this.pendingPromptCancel)||void 0===t||t.call(this);const[o,n]=this.ctx.withCancel();this.pendingPromptCancel=n;try{yield this.processPrompt(e,o)}catch(e){if(o.canceled)return{stopReason:"cancelled"};throw e}finally{this.pendingPromptCancel=null}return o.canceled?{stopReason:"cancelled"}:{stopReason:"end_turn"}}))}';
const ACP_HANDLE_PROMPT_AFTER =
  'handlePrompt(e){return $(this,void 0,void 0,(function*(){var t;null===(t=this.pendingPromptCancel)||void 0===t||t.call(this);const[o,n]=this.ctx.withCancel();this.pendingPromptCancel=n,this._lastAssistantMessage="";try{yield this.processPrompt(e,o)}catch(e){if(o.canceled)return{stopReason:"cancelled"};throw e}finally{this.pendingPromptCancel=null}if(o.canceled)return{stopReason:"cancelled"};try{if(this.hookExecutor){const e=yield this.hookExecutor.executeHookForStep("stop",{conversation_id:this.sessionId,status:"success",model:this.currentModel&&this.currentModel.modelId?this.currentModel.modelId:"unknown",loop_count:0,last_assistant_message:this._lastAssistantMessage||void 0});if((null==e?void 0:e.permission)==="deny"&&e.user_message&&!o.canceled)yield this.processPrompt({prompt:[{type:"text",text:e.user_message}]},o)}}catch(e){(0,b.debugLog)("Stop hook execution failed in ACP handlePrompt:",e)}try{const e=require("node:child_process"),t=require("node:os"),n=require("node:path"),s=n.join(t.homedir(),".claude","hooks","stop_check_links.py"),r=e.spawnSync("python3",[s],{input:JSON.stringify({stop_reason:"end_turn",last_assistant_message:this._lastAssistantMessage||""}),encoding:"utf8"});if(0===r.status&&r.stdout){const e=JSON.parse(r.stdout);if((null==e?void 0:e.decision)==="block"&&e.reason&&!o.canceled)yield this.processPrompt({prompt:[{type:"text",text:e.reason}]},o)}}catch(e){(0,b.debugLog)("Direct stop_check_links fallback failed:",e)}return o.canceled?{stopReason:"cancelled"}:{stopReason:"end_turn"}}))}';
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
      process.exit(1);
    }
  }

  let patched = source;
  let changed = false;
  let rawInputPatched = false;
  let taskOutputPatched = false;
  let taskNotificationPatched = false;
  let stopGatePatchCount = 0;
  let beforeSubmitPatchCount = 0;
  let claudeBridgePatched = false;
  let modelRequestFormatPatched = false;
  let acpStopInvokePatched = false;
  let acpAssistantCapturePatched = false;

  const matchesAcpBundle =
    source.includes(REQUIRED_MARKER) && source.includes("sentToolCalls");
  if (matchesAcpBundle && patched.includes(BEFORE)) {
    patched = patched.replace(BEFORE, AFTER);
    rawInputPatched = true;
    changed = true;
  }
  if (matchesAcpBundle && patched.includes(TASK_OUTPUT_BEFORE)) {
    patched = patched.replace(TASK_OUTPUT_BEFORE, TASK_OUTPUT_AFTER);
    taskOutputPatched = true;
    changed = true;
  }
  if (matchesAcpBundle && patched.includes(TASK_NOTIFICATION_BEFORE)) {
    patched = patched.replace(TASK_NOTIFICATION_BEFORE, TASK_NOTIFICATION_AFTER);
    taskNotificationPatched = true;
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

  if (
    patched.includes("./src/acp/agent-session.ts") &&
    patched.includes(ACP_HANDLE_PROMPT_BEFORE)
  ) {
    if (patched.includes(ACP_SESSION_CTOR_BEFORE)) {
      patched = patched.replace(ACP_SESSION_CTOR_BEFORE, ACP_SESSION_CTOR_AFTER);
      changed = true;
    }
    if (patched.includes(ACP_SESSION_NEW_BEFORE)) {
      patched = patched.replace(ACP_SESSION_NEW_BEFORE, ACP_SESSION_NEW_AFTER);
      changed = true;
    }
    if (patched.includes(ACP_SESSION_LOAD_BEFORE)) {
      patched = patched.replace(ACP_SESSION_LOAD_BEFORE, ACP_SESSION_LOAD_AFTER);
      changed = true;
    }
    if (patched.includes(ACP_SEND_AGENT_CHUNK_BEFORE)) {
      patched = patched.replace(ACP_SEND_AGENT_CHUNK_BEFORE, ACP_SEND_AGENT_CHUNK_AFTER);
      changed = true;
      acpAssistantCapturePatched = true;
    }
    patched = patched.replace(ACP_HANDLE_PROMPT_BEFORE, ACP_HANDLE_PROMPT_AFTER);
    changed = true;
    acpStopInvokePatched = true;
  }

  if (!changed) {
    return originalLoader(module, filename);
  }
  debugLog(
    "[agent-patched] applied ACP patches to " +
      filename +
      ` (rawInput=${rawInputPatched ? "yes" : "no"}, taskOutput=${taskOutputPatched ? "yes" : "no"}, taskNotification=${taskNotificationPatched ? "yes" : "no"}, stopGate=${stopGatePatchCount}, beforeSubmit=${beforeSubmitPatchCount}, claudeBridge=${claudeBridgePatched ? "yes" : "no"}, modelRequestFormat=${modelRequestFormatPatched ? "yes" : "no"}, acpStopInvoke=${acpStopInvokePatched ? "yes" : "no"}, acpAssistantCapture=${acpAssistantCapturePatched ? "yes" : "no"})`,
  );
  module._compile(patched, filename);
};
