(() => {
  "use strict";

  const updateViewportVariables = () => {
    const viewport = window.visualViewport;
    const width = Math.max(1, viewport ? viewport.width : window.innerWidth);
    const height = Math.max(1, viewport ? viewport.height : window.innerHeight);
    const left = viewport ? viewport.offsetLeft : 0;
    const top = viewport ? viewport.offsetTop : 0;
    const root = document.documentElement;
    root.style.setProperty("--wwpo-viewport-width", `${width}px`);
    root.style.setProperty("--wwpo-viewport-height", `${height}px`);
    root.style.setProperty("--wwpo-viewport-left", `${left}px`);
    root.style.setProperty("--wwpo-viewport-top", `${top}px`);
  };

  updateViewportVariables();
  window.addEventListener("resize", updateViewportVariables, { passive: true });
  window.addEventListener("pageshow", updateViewportVariables, { passive: true });
  if (window.visualViewport) {
    window.visualViewport.addEventListener("resize", updateViewportVariables, { passive: true });
    window.visualViewport.addEventListener("scroll", updateViewportVariables, { passive: true });
  }
})();
