const HELPER_URL = "http://127.0.0.1:43128/action";
const HELPER_TOKEN = "8a6f67fb36e94a9f84a25d874906f1d4e60b9c4ae36246d8b4d7a2192e77c685";

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const supported = message?.type === "translate" || message?.type === "speak";
  if (!supported || typeof message.text !== "string") {
    return false;
  }

  fetch(HELPER_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-English-Learning-Assistant-Token": HELPER_TOKEN
    },
    body: JSON.stringify({
      type: message.type,
      text: message.text.slice(0, message.type === "speak" ? 2000 : 6000),
      rate: Number(message.rate) || 0.9
    })
  })
    .then(async (response) => {
      const payload = await response.json();
      if (!response.ok && !payload?.error) payload.error = `本地助手返回错误 ${response.status}`;
      sendResponse(payload);
    })
    .catch((error) => sendResponse({
      success: false,
      error: `无法连接本地助手：${error.message}`
    }));
  return true;
});
