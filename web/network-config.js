(() => {
  const isLocal = location.hostname === "localhost" || location.hostname === "127.0.0.1";
  window.WWPO_CONFIG = {
    serverUrl: isLocal
      ? "ws://127.0.0.1:7000"
      : `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}/ws`
  };
})();
