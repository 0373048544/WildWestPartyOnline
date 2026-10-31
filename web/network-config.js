// Deployment-specific endpoint, loaded by the Godot export HTML.
// HTTPS pages require WSS. No server URL appears in the player-facing forms.
window.WWPO_CONFIG = {
  serverUrl: location.protocol === "https:"
    ? "wss://" + location.hostname + "/ws"
    : "ws://" + location.hostname + ":7000"
};
