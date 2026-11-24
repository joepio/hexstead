(() => {
  if (parent === window) return;
  try { if (parent.location.origin !== location.origin) return; } catch { return; }
  const channel = 'splitscreen-club-webgame-v1';
  const origin = location.origin;
  let receive;
  window.SplitscreenClubWebGame = {
    bindReceiver(fn) { receive = fn; },
    sendToParent(json) { parent.postMessage({channel, payload: JSON.parse(json)}, origin); }
  };
  addEventListener('message', event => {
    if (event.source !== parent || event.origin !== origin || event.data?.channel !== channel || !receive) return;
    receive(JSON.stringify(event.data.payload));
  });
})();