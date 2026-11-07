(function () {
  "use strict";
  let client = null;
  let localAudioTrack = null;
  let joining = false;

  async function leaveCurrent() {
    if (localAudioTrack) {
      try { localAudioTrack.stop(); localAudioTrack.close(); } catch (_) {}
      localAudioTrack = null;
    }
    if (client) {
      try { await client.leave(); } catch (_) {}
      client = null;
    }
  }

  async function join(appId, channel, token, uid, publish) {
    if (!window.AgoraRTC) throw new Error("تعذر تحميل مكتبة Agora");
    if (joining) throw new Error("اتصال الصوت قيد التجهيز");
    joining = true;
    try {
      await leaveCurrent();
      client = window.AgoraRTC.createClient({ mode: "live", codec: "vp8" });
      client.on("user-published", async function (user, mediaType) {
        try {
          await client.subscribe(user, mediaType);
          if (mediaType === "audio" && user.audioTrack) user.audioTrack.play();
        } catch (error) { console.warn("[HappyLive Agora] subscribe failed", error); }
      });
      await client.join(appId, channel, token, Number(uid));
      await client.setClientRole(publish ? "host" : "audience");
      if (publish) {
        localAudioTrack = await window.AgoraRTC.createMicrophoneAudioTrack();
        await client.publish([localAudioTrack]);
      }
      return true;
    } finally {
      joining = false;
    }
  }

  async function setMuted(muted) {
    if (!localAudioTrack) return false;
    await localAudioTrack.setEnabled(!muted);
    return true;
  }

  window.happyLiveAgora = {
    join: join, leave: leaveCurrent, setMuted: setMuted,
    isLoaded: function () { return !!window.AgoraRTC; }
  };
})();
