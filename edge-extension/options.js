const enabled = document.getElementById("enabled");
const status = document.getElementById("status");

chrome.storage.sync.get({ enabled: true }, (settings) => {
  enabled.checked = settings.enabled !== false;
});

function save() {
  chrome.storage.sync.set({ enabled: enabled.checked }, () => {
    status.textContent = "已保存";
    setTimeout(() => { status.textContent = ""; }, 1200);
  });
}

enabled.addEventListener("change", save);
