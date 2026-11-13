document.getElementById('close').addEventListener('click', () => window.close());

// What the panel is to its extension (#265). In Chrome a side panel page is not a tab:
// tabs.getCurrent() gives undefined, the worker sees no sender.tab on the panel's messages and
// ports, and runtime.getContexts() lists the panel as SIDE_PANEL with no tab. Claude in
// Chrome's panel refuses to start, and its worker refuses the panel's bridge, unless that holds.
// The scenario reads `answers` (from://debug?sidePanelJS=answers).
var answers = 'pending';
(async () => {
  const current = (await chrome.tabs.getCurrent()) ? 'tab' : 'none';
  const message = await chrome.runtime.sendMessage({ panel: 'sender' });
  const port = chrome.runtime.connect({ name: 'panel' });
  port.onMessage.addListener(({ port: portSender, context }) => {
    answers = `current-${current}-message-${message}-port-${portSender}-context-${context}`;
  });
})();

// Which tab the panel's extension takes for the one the user is looking at (ChatGPT's panel
// reads chrome.tabs.query({active: true, lastFocusedWindow: true})[0]). In Chrome that is the
// page beside the panel, never the panel. probeTabs() fills `tabsSeen`.
var tabsSeen = 'pending';
function probeTabs() {
  tabsSeen = 'pending';
  const kind = (t) => !t ? 'none' : (t.url || t.pendingUrl || '').startsWith(location.origin) ? 'panel'
    : /^https?:/.test(t.url || t.pendingUrl || '') ? 'page' : 'other';
  (async () => {
    const [last] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    const [current] = await chrome.tabs.query({ active: true, currentWindow: true });
    const all = await chrome.tabs.query({});
    const listed = all.some((t) => kind(t) === 'panel') ? 'panel' : 'none';
    const win = await chrome.windows.getCurrent();
    const windowOf = current && win.id === current.windowId ? 'page' : 'other';
    tabsSeen = `last-${kind(last)}-current-${kind(current)}-listed-${listed}-window-${windowOf}`;
  })().catch((e) => { tabsSeen = 'error-' + e.message; });
  return 'started';
}
