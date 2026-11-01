// Deployment-specific endpoint, loaded by the Godot export HTML.
// Local browser builds use localhost. Public HTTPS builds must use the Koyeb WSS URL.
// After Koyeb deploys successfully, replace REPLACE-ME with the real service hostname.
(() => {
  const localHosts = new Set(["localhost", "127.0.0.1"]);
  const isLocal = localHosts.has(location.hostname);

  window.WWPO_CONFIG = {
    serverUrl: isLocal
      ? "ws://127.0.0.1:7000"
      : "wss://REPLACE-ME.koyeb.app"
  };
})();
