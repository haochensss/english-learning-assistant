(() => {
  if (window.__englishLearningAssistantLoaded) return;
  window.__englishLearningAssistantLoaded = true;

  const state = {
    text: "",
    rate: 0.9,
    enabled: true,
    buttonHost: null,
    resultHost: null
  };

  chrome.storage.sync.get({ rate: 0.9, enabled: true }, (settings) => {
    state.rate = Number(settings.rate) || 0.9;
    state.enabled = settings.enabled !== false;
  });

  chrome.storage.onChanged.addListener((changes) => {
    if (changes.rate) state.rate = Number(changes.rate.newValue) || 0.9;
    if (changes.enabled) {
      state.enabled = changes.enabled.newValue !== false;
      if (!state.enabled) hideAll();
    }
  });

  function speak(text, rect, button) {
    if (!text) return;
    const original = button?.innerHTML;
    if (button) {
      button.disabled = true;
      button.textContent = "生成语音…";
    }
    chrome.runtime.sendMessage({ type: "speak", text, rate: state.rate }, (response) => {
      if (button) {
        button.disabled = false;
        button.innerHTML = original;
      }
      if (chrome.runtime.lastError) {
        showResult(rect || { left: 8, bottom: 8 }, "朗读失败", chrome.runtime.lastError.message, true);
        return;
      }
      if (!response?.success) {
        showResult(rect || { left: 8, bottom: 8 }, "朗读失败", response?.error || "未知错误", true);
      }
    });
  }

  function makeHost(id) {
    const old = document.getElementById(id);
    if (old) old.remove();
    const host = document.createElement("div");
    host.id = id;
    host.style.position = "fixed";
    host.style.zIndex = "2147483647";
    document.documentElement.appendChild(host);
    return { host, root: host.attachShadow({ mode: "closed" }) };
  }

  function buttonCss() {
    return `
      * { box-sizing: border-box; }
      .bar { width:max-content; max-width:calc(100vw - 16px); min-height:34px; display:flex;
        align-items:stretch; overflow:hidden; padding:0; border:1px solid #344158;
        border-radius:11px; color:#f2f5fa; background:#151d2b;
        box-shadow:0 10px 24px rgba(0,0,0,.42); font:11.5px/1.2 -apple-system,
        BlinkMacSystemFont,"Segoe UI","Microsoft YaHei UI","Microsoft YaHei",sans-serif; }
      button { min-height:34px; display:inline-flex; align-items:center; justify-content:center;
        gap:5px; padding:0 7px; border:0; border-right:1px solid #344158;
        border-radius:0; color:inherit; background:#182231; cursor:pointer;
        white-space:nowrap; font:inherit; font-weight:550; transition:background .15s ease,
        color .15s ease, box-shadow .15s ease; }
      button:hover { color:#fff; background:#263247; }
      button:active { background:#334158; }
      button:focus-visible { position:relative; z-index:1; outline:2px solid #91a4ff;
        outline-offset:-3px; }
      button.primary { border-right-color:#7189f5; color:#fff; background:#526fe7;
        box-shadow:inset 0 0 0 1px rgba(166,183,255,.16),
        0 6px 16px rgba(43,69,178,.28); }
      button.primary:hover { background:#6480f0; }
      button.primary:active { background:#455fce; }
      button:disabled { color:#b9c2d3; opacity:.72; cursor:wait; box-shadow:none; }
      button.close { width:36px; min-width:36px; padding:0 6px; border-right:0;
        background:#151d2b; }
      button.close:hover { background:#202b3d; }
      svg { width:12px; height:12px; flex:0 0 auto; box-sizing:content-box; padding:3px;
        border-radius:6px; color:#dce5ff; background:#263143; fill:none; stroke:currentColor;
        stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
      button.primary svg { color:#fff; background:rgba(23,34,78,.34); }
      button.close svg { width:14px; height:14px; color:#c3ccdc; background:#263143; }
    `;
  }

  function rateLabel() {
    if (state.rate <= 0.8) return "语速：慢速";
    if (state.rate >= 1.0) return "语速：快速";
    return "语速：正常";
  }

  function cycleRate(button, label) {
    if (state.rate <= 0.8) state.rate = 1.1;
    else if (state.rate >= 1.0) state.rate = 0.9;
    else state.rate = 0.7;
    label.textContent = rateLabel();
    chrome.storage.sync.set({ rate: state.rate });
    button.setAttribute("aria-label", `${rateLabel()}，点击切换`);
  }

  function showButtons(rect, text) {
    hideButtons();
    state.text = text;
    const { host, root } = makeHost("english-learning-assistant-buttons");
    state.buttonHost = host;
    host.style.left = "8px";
    host.style.top = "8px";

    const style = document.createElement("style");
    style.textContent = buttonCss();
    const bar = document.createElement("div");
    bar.className = "bar";

    const speakButton = document.createElement("button");
    const speakLabel = document.createElement("span");
    speakLabel.textContent = "朗读";
    speakButton.append(makeIcon("speaker"), speakLabel);
    speakButton.addEventListener("mousedown", (event) => event.preventDefault());
    speakButton.addEventListener("click", () => speak(state.text, rect, speakButton));

    const translateButton = document.createElement("button");
    translateButton.className = "primary";
    const translateLabel = document.createElement("span");
    translateLabel.textContent = "中↔英 翻译";
    translateButton.append(makeIcon("languages"), translateLabel);
    translateButton.addEventListener("mousedown", (event) => event.preventDefault());
    translateButton.addEventListener("click", () => translate(state.text, rect, translateButton));

    const rateButton = document.createElement("button");
    const rateText = document.createElement("span");
    rateText.textContent = rateLabel();
    rateButton.setAttribute("aria-label", `${rateLabel()}，点击切换`);
    rateButton.append(makeIcon("speed"), rateText);
    rateButton.addEventListener("mousedown", (event) => event.preventDefault());
    rateButton.addEventListener("click", () => cycleRate(rateButton, rateText));

    const closeButton = document.createElement("button");
    closeButton.className = "close";
    closeButton.setAttribute("aria-label", "关闭");
    closeButton.append(makeIcon("close"));
    closeButton.addEventListener("mousedown", (event) => event.preventDefault());
    closeButton.addEventListener("click", hideButtons);

    bar.append(speakButton, translateButton, rateButton, closeButton);
    root.append(style, bar);

    const bounds = bar.getBoundingClientRect();
    const left = rect.left + (rect.width || 0) / 2 - bounds.width / 2;
    const below = rect.bottom + 8;
    const top = below + bounds.height <= window.innerHeight - 8
      ? below : Math.max(8, rect.top - bounds.height - 8);
    host.style.left = `${Math.min(Math.max(8, left), window.innerWidth - bounds.width - 8)}px`;
    host.style.top = `${top}px`;
  }

  function translate(text, rect, button) {
    const original = button.innerHTML;
    button.disabled = true;
    button.textContent = "Codex 翻译中…";
    showLoading(rect, "Codex 翻译中…");
    chrome.runtime.sendMessage({ type: "translate", text }, (response) => {
      button.disabled = false;
      button.innerHTML = original;
      if (chrome.runtime.lastError) {
        showResult(rect, "翻译失败", chrome.runtime.lastError.message, true);
        return;
      }
      if (!response?.success) {
        showResult(rect, "翻译失败", response?.error || "未知错误", true);
        return;
      }
      showResult(rect, "Codex 翻译", response.result, false);
    });
  }

  function showLoading(rect, message) {
    hideResult();
    const { host, root } = makeHost("english-learning-assistant-result");
    state.resultHost = host;
    host.style.left = `${Math.min(Math.max(8, rect.left), window.innerWidth - 300)}px`;
    host.style.top = `${Math.min(window.innerHeight - 90, rect.bottom + 48)}px`;

    const style = document.createElement("style");
    style.textContent = `
      * { box-sizing:border-box; }
      .loading { min-width:260px; display:flex; align-items:center; justify-content:center; gap:10px;
        padding:14px 18px; border-radius:10px; background:#17233a; color:#fff;
        box-shadow:0 10px 30px rgba(0,0,0,.32); font:15px/1.3 -apple-system,
        BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif; }
      .spinner { width:16px; height:16px; border:2px solid rgba(255,255,255,.35);
        border-top-color:#fff; border-radius:50%; animation:spin .8s linear infinite; }
      @keyframes spin { to { transform:rotate(360deg); } }
    `;
    const loading = document.createElement("div");
    loading.className = "loading";
    const spinner = document.createElement("span");
    spinner.className = "spinner";
    const text = document.createElement("span");
    text.textContent = message;
    loading.append(spinner, text);
    root.append(style, loading);
  }

  function showResult(rect, title, text, isError) {
    hideResult();
    const { host, root } = makeHost("english-learning-assistant-result");
    state.resultHost = host;
    const cardWidth = Math.min(400, Math.max(280,
      Math.round((rect.width || 0) * 0.75)));
    host.style.width = `${Math.min(cardWidth, window.innerWidth - 16)}px`;
    host.style.left = `${Math.min(Math.max(8, rect.left + (rect.width || 0) / 2 - cardWidth / 2),
      window.innerWidth - cardWidth - 8)}px`;
    host.style.top = `${Math.max(8, rect.bottom + 48)}px`;

    const style = document.createElement("style");
    style.textContent = `
      * { box-sizing:border-box; }
      .card { width:100%; overflow:hidden; border-radius:11px;
        background:#151d2b; color:#f5f7fb; box-shadow:0 18px 45px rgba(0,0,0,.48);
        border:1px solid #344158; font:12px/1.45 -apple-system,BlinkMacSystemFont,
        "Segoe UI","Microsoft YaHei",sans-serif; }
      .header { display:flex; align-items:center; gap:7px; padding:8px 9px 6px 12px; }
      .mark { width:24px; height:24px; flex:0 0 24px; display:flex; align-items:center;
        justify-content:center; border-radius:7px; color:#dce5ff; background:#263c79; }
      .title { flex:1; color:${isError ? "#ffb4ad" : "#aebfff"}; font-size:13px;
        line-height:1.3; font-weight:600; }
      .close { width:28px; height:28px; display:flex; align-items:center; justify-content:center;
        padding:0; border:1px solid transparent; border-radius:7px; color:#c3ccdc;
        background:#263143; cursor:pointer; }
      .close:hover { color:#fff; background:#344158; }
      .text { margin:0 12px; padding:8px 10px; border-left:2px solid #7891ff;
        border-radius:0 8px 8px 0; color:#f7f9fc; background:#101724;
        font-size:14px; line-height:1.5; white-space:pre-wrap; overflow-wrap:anywhere;
        max-height:180px; overflow:auto; }
      .card.error .text { border-left-color:#f97066; color:#ffd5d1; }
      .actions { display:flex; align-items:center; gap:7px; padding:8px 12px 10px; }
      .action { min-height:32px; display:inline-flex; align-items:center; justify-content:center;
        gap:5px; padding:0 10px; border-radius:7px; font:inherit; font-weight:600;
        cursor:pointer; }
      .read { border:1px solid #46546b; color:#f2f5fa; background:#273247; }
      .read:hover { background:#334158; }
      .copy { border:1px solid #7189f5; color:#fff; background:#526fe7;
        box-shadow:0 6px 16px rgba(43,69,178,.34); }
      .copy:hover { background:#6480f0; }
      .copy.copied { border-color:#56c99a; background:#277e62; box-shadow:none; }
      button:disabled { opacity:.68; cursor:wait; }
      svg { width:17px; height:17px; flex:0 0 auto; fill:none; stroke:currentColor;
        stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
    `;
    const card = document.createElement("div");
    card.className = "card";
    if (isError) card.classList.add("error");
    const header = document.createElement("div");
    header.className = "header";
    const mark = document.createElement("span");
    mark.className = "mark";
    mark.append(makeIcon(isError ? "warning" : "languages"));
    const titleText = document.createElement("span");
    titleText.className = "title";
    titleText.textContent = isError ? title : "英语学习助手 · 翻译";
    const close = document.createElement("button");
    close.className = "close";
    close.setAttribute("aria-label", "关闭");
    close.append(makeIcon("close"));
    close.onclick = hideResult;
    header.append(mark, titleText, close);
    const body = document.createElement("div");
    body.className = "text";
    body.textContent = text;
    const actions = document.createElement("div");
    actions.className = "actions";
    if (!isError) {
      const read = document.createElement("button");
      read.className = "action read";
      const readLabel = document.createElement("span");
      readLabel.textContent = "朗读译文";
      read.append(makeIcon("speaker"), readLabel);
      read.onclick = () => speak(text, rect, read);
      const copy = document.createElement("button");
      copy.className = "action copy";
      const copyLabel = document.createElement("span");
      copyLabel.textContent = "复制译文";
      copy.append(makeIcon("copy"), copyLabel);
      copy.onclick = async () => {
        await navigator.clipboard.writeText(text);
        copy.classList.add("copied");
        copyLabel.textContent = "已复制";
      };
      actions.append(read, copy);
    }
    card.append(header, body);
    if (!isError) card.append(actions);
    root.append(style, card);

    requestAnimationFrame(() => {
      const box = host.getBoundingClientRect();
      if (box.bottom > window.innerHeight - 8) {
        host.style.top = `${Math.max(8, rect.top - box.height - 8)}px`;
      }
    });
  }

  function makeIcon(name) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    const icons = {
      speaker: '<path d="M11 5 6 9H2v6h4l5 4z"></path><path d="M15.5 8.5a5 5 0 0 1 0 7"></path><path d="M18 6a8.5 8.5 0 0 1 0 12"></path>',
      copy: '<rect width="14" height="14" x="8" y="8" rx="2"></rect><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"></path>',
      close: '<path d="M18 6 6 18"></path><path d="m6 6 12 12"></path>',
      warning: '<path d="M10.3 2.9 1.8 17a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 2.9a2 2 0 0 0-3.4 0Z"></path><path d="M12 9v4"></path><path d="M12 17h.01"></path>',
      languages: '<path d="m5 8 6 6"></path><path d="m4 14 6-6 2-3"></path><path d="M2 5h12"></path><path d="M7 2h1"></path><path d="m22 22-5-10-5 10"></path><path d="M14 18h6"></path>',
      speed: '<path d="M20 13a8 8 0 1 0-16 0"></path><path d="m12 13 4-4"></path><path d="M4 17h16"></path>'
    };
    svg.innerHTML = icons[name] || icons.languages;
    return svg;
  }

  function hideButtons() {
    state.buttonHost?.remove();
    state.buttonHost = null;
  }

  function hideResult() {
    state.resultHost?.remove();
    state.resultHost = null;
  }

  function hideAll() {
    hideButtons();
    hideResult();
  }

  function inspectSelection() {
    if (!state.enabled) return;
    setTimeout(() => {
      const selection = window.getSelection();
      const text = selection?.toString().trim();
      if (!text || selection.rangeCount === 0) {
        hideButtons();
        return;
      }
      const rect = selection.getRangeAt(0).getBoundingClientRect();
      if (!rect || (!rect.width && !rect.height)) return;
      showButtons(rect, text.slice(0, 6000));
    }, 20);
  }

  function isAssistantEvent(event) {
    const path = typeof event.composedPath === "function" ? event.composedPath() : [];
    return (state.buttonHost && (event.target === state.buttonHost || path.includes(state.buttonHost))) ||
      (state.resultHost && (event.target === state.resultHost || path.includes(state.resultHost)));
  }

  document.addEventListener("mouseup", (event) => {
    // 点击助手自身时不能再次检查仍然高亮的页面选区，否则关闭后会立刻重建工具条。
    if (!isAssistantEvent(event)) inspectSelection();
  }, true);
  document.addEventListener("keyup", (event) => {
    if (event.key === "Shift" || event.key.startsWith("Arrow")) inspectSelection();
  }, true);
  window.addEventListener("scroll", hideButtons, true);
  document.addEventListener("mousedown", (event) => {
    if (!isAssistantEvent(event)) hideButtons();
  }, true);
})();
