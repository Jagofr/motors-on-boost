/* Runtime deployment environment descriptor (default: IIS primary host).
 * Overwritten automatically during GitHub Pages static packaging (scripts/prepare-gh-pages.js).
 */
window.__MOB_ENV__ = {
  target: "iis",
  enableCoiServiceWorker: false,
  relayMode: "same-origin",
  relayOrigin: "",
  staticOfflineHosts: []
};
