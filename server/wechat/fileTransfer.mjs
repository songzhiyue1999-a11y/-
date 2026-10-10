import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { getPublishedCoverFile } from "../codex/coverImage.mjs";
import { CodexApiError } from "../codex/validation.mjs";

const helperPath = fileURLToPath(new URL("./fileTransfer.swift", import.meta.url));
let sending = false;

function runHelper(action, input = null) {
  if (process.platform !== "darwin") {
    throw new CodexApiError("MAC_ONLY", "微信文件传输助手直发目前仅支持 Mac 微信。", 501);
  }
  return new Promise((resolve, reject) => {
    const child = spawn("/usr/bin/swift", [helperPath, action], {
      env: {
        ...process.env,
        CLANG_MODULE_CACHE_PATH: "/private/tmp/xm-xhs-swift-cache",
        SWIFT_MODULE_CACHE_PATH: "/private/tmp/xm-xhs-swift-cache",
      },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => child.kill("SIGTERM"), 30_000);
    child.stdout.on("data", (chunk) => { stdout += chunk.toString("utf8"); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString("utf8"); });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(new CodexApiError("WECHAT_HELPER_FAILED", `无法启动微信发送助手：${error.message}`, 503));
    });
    child.on("close", () => {
      clearTimeout(timer);
      let result;
      try {
        result = JSON.parse(stdout.trim().split("\n").at(-1));
      } catch {
        reject(new CodexApiError("WECHAT_HELPER_FAILED", `微信发送助手执行失败：${stderr.trim().slice(0, 300) || "无有效响应"}`, 503));
        return;
      }
      resolve(result);
    });
    child.stdin.end(input ? JSON.stringify(input) : "");
  });
}

export async function wechatStatus(prompt = false, screenPrompt = false) {
  return runHelper(screenPrompt ? "request-screen-recording" : prompt ? "request-permission" : "status");
}

export async function sendToFileTransfer(payload) {
  if (sending) throw new CodexApiError("WECHAT_BUSY", "上一条微信发送仍在进行，请稍后再试。", 409);
  const title = typeof payload.title === "string" ? payload.title.trim() : "";
  const body = typeof payload.body === "string" ? payload.body.trim() : "";
  if (!title || !body || title.length > 120 || body.length > 10_000) {
    throw new CodexApiError("BAD_REQUEST", "请先选择包含标题和正文的文案。", 400);
  }
  const imagePath = await getPublishedCoverFile(payload.coverSrc);
  sending = true;
  try {
    return await runHelper("send", { text: `${title}\n\n${body}`, imagePath });
  } finally {
    sending = false;
  }
}
