// Flutter <-> scene messaging.
//
// Flutter -> JS: window.runlah.receive(jsonString) on mobile WebViews,
//                window.postMessage(jsonString) into the Flutter-web iframe.
// JS -> Flutter: window.RunLah.postMessage(json) (webview_flutter channel)
//                or window.parent.postMessage(json, '*') (web iframe).

const COMMANDS = new Set(['init', 'play', 'pause', 'seek', 'speed', 'follow', 'mode']);
const channel = new URLSearchParams(location.search).get('ch');

export function post(msg) {
  if (channel) msg.ch = channel;
  const json = JSON.stringify(msg);
  try {
    if (window.RunLah && typeof window.RunLah.postMessage === 'function') {
      window.RunLah.postMessage(json);
    } else if (window.parent && window.parent !== window) {
      window.parent.postMessage(json, '*');
    }
  } catch (e) {
    // Host went away (page closing); nothing to do.
  }
}

export function listen(handler) {
  const receive = (raw) => {
    let m = raw;
    if (typeof m === 'string') {
      try {
        m = JSON.parse(m);
      } catch (e) {
        return;
      }
    }
    if (!m || typeof m !== 'object' || !COMMANDS.has(m.type)) return;
    try {
      handler(m);
    } catch (e) {
      post({ type: 'error', message: String((e && e.stack) || e) });
    }
  };
  window.runlah = { receive };
  window.addEventListener('message', (e) => {
    if (e.source === window) return;
    receive(e.data);
  });
}
