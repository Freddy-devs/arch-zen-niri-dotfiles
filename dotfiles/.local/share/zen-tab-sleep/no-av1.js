// La gráfica Intel UHD 620 decodifica H.264/VP9 por hardware pero no AV1: si YouTube manda
// AV1, el video lo decodifica la CPU. Diciendo que AV1 no se soporta, YouTube manda VP9.
(() => {
  const esAv1 = t => /av01|av1/i.test(String(t));
  const ms = window.MediaSource;
  if (ms && ms.isTypeSupported) {
    const orig = ms.isTypeSupported.bind(ms);
    ms.isTypeSupported = t => !esAv1(t) && orig(t);
  }
  const canPlay = HTMLMediaElement.prototype.canPlayType;
  HTMLMediaElement.prototype.canPlayType = function (t) { return esAv1(t) ? "" : canPlay.call(this, t); };
  const mc = navigator.mediaCapabilities;
  if (mc && mc.decodingInfo) {
    const orig = mc.decodingInfo.bind(mc);
    mc.decodingInfo = cfg => esAv1(cfg?.video?.contentType)
      ? Promise.resolve({ supported: false, smooth: false, powerEfficient: false })
      : orig(cfg);
  }
})();
