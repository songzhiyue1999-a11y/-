import { useEffect, useState } from "react";
import { requestWechatSend, requestWechatStatus } from "./codexClient.js";

export function WechatShareDialog({ draft, coverImage, onClose }) {
  const [status, setStatus] = useState({ code: "CHECKING", message: "正在检查 Mac 微信与辅助功能权限…" });
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [sent, setSent] = useState(false);
  const content = `${draft.title.trim()}\n\n${draft.body.trim()}`;

  const checkStatus = async (requestPermission = false, requestScreenRecording = false) => {
    setStatus({ code: "CHECKING", message: "正在检查 Mac 微信与辅助功能权限…" });
    try {
      const response = await requestWechatStatus(requestPermission, requestScreenRecording);
      setStatus(response.status);
    } catch (error) {
      setStatus({ code: error.code || "STATUS_FAILED", message: error.message });
    }
  };

  useEffect(() => {
    checkStatus();
    const onEscape = (event) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onEscape);
    return () => window.removeEventListener("keydown", onEscape);
  }, []);

  const copyText = async () => {
    try {
      await navigator.clipboard.writeText(content);
      setMessage("标题和正文已复制，可粘贴到微信文件传输助手。");
    } catch {
      setMessage("浏览器未允许复制，请选中文案手动复制。");
    }
  };

  const downloadCover = async () => {
    try {
      const response = await fetch(coverImage.src);
      if (!response.ok) throw new Error("封面图文件已失效，请重新生成。");
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `${draft.title.trim().replace(/[\\/:*?"<>|]/g, "-").slice(0, 48) || "小红书封面"}.png`;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30_000);
      setMessage("已开始下载封面图，请在浏览器下载记录中确认。");
    } catch (error) {
      setMessage(error.message || "下载封面图失败。");
    }
  };

  const send = async () => {
    setBusy(true);
    setMessage("");
    try {
      const response = await requestWechatSend({
        title: draft.title,
        body: draft.body,
        coverSrc: coverImage.src,
      });
      setSent(true);
      setMessage(response.result.message);
    } catch (error) {
      setMessage(error.message || "发送失败，请检查微信当前会话。");
      if (error.code === "ACCESSIBILITY_REQUIRED") checkStatus();
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="wechat-dialog-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <section className="wechat-dialog" role="dialog" aria-modal="true" aria-labelledby="wechat-share-title">
        <header>
          <div>
            <span className="wechat-eyebrow">微信 · 发送前核对</span>
            <h2 id="wechat-share-title">发送到文件传输助手</h2>
            <p>将以两条消息发送当前封面图与标题正文。请先在 Mac 微信中打开“文件传输助手”会话。</p>
          </div>
          <button className="wechat-close" type="button" onClick={onClose} aria-label="关闭发送预览">×</button>
        </header>
        <div className="wechat-share-preview">
          <img src={coverImage.src} alt={coverImage.alt || "待发送封面"} />
          <div>
            <strong>{draft.title}</strong>
            <p>{draft.body}</p>
          </div>
        </div>
        <div className={`wechat-status ${status.code === "READY" ? "ready" : ""}`} role="status">
          {status.message}
        </div>
        {message && <p className={`wechat-feedback ${sent ? "success" : ""}`} role="status">{message}</p>}
        <div className="wechat-share-actions">
          <button className="primary-button" type="button" onClick={send} disabled={busy || status.code !== "READY" || sent}>
            {busy ? "正在交给微信…" : sent ? "已提交发送" : "确认发送到文件传输助手"}
          </button>
          {status.code === "ACCESSIBILITY_REQUIRED" && (
            <button className="soft-button" type="button" onClick={() => checkStatus(true)}>授权辅助功能</button>
          )}
          {status.code === "SCREEN_RECORDING_REQUIRED" && (
            <button className="soft-button" type="button" onClick={() => checkStatus(false, true)}>授权录屏</button>
          )}
          <button className="soft-button" type="button" onClick={() => checkStatus()}>重新检查</button>
        </div>
        <div className="wechat-manual-actions">
          <span>手动发送</span>
          <button type="button" onClick={copyText}>复制标题与正文</button>
          <button type="button" onClick={downloadCover}>下载封面图</button>
          <a href="https://filehelper.weixin.qq.com/" target="_blank" rel="noreferrer">打开网页版文件传输助手 ↗</a>
        </div>
      </section>
    </div>
  );
}
