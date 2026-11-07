(function () {
  "use strict";
  let client = null;
  let localAudioTrack = null;
  let joining = false;
  let audioUnlockButton = null;

  function showAudioUnlock() {
    if (audioUnlockButton || !document.body) return;
    audioUnlockButton = document.createElement("button");
    audioUnlockButton.type = "button";
    audioUnlockButton.textContent = "اضغط لتفعيل صوت الغرفة";
    audioUnlockButton.setAttribute("aria-label", "تفعيل صوت الغرفة");
    audioUnlockButton.style.cssText = "position:fixed;z-index:2147483647;left:50%;bottom:26px;transform:translateX(-50%);padding:13px 20px;border:1px solid rgba(232,196,119,.7);border-radius:24px;background:linear-gradient(110deg,#3a2948,#17131f);color:#fff;font:700 14px system-ui;box-shadow:0 8px 28px #0008";
    audioUnlockButton.addEventListener("click", function () {
      if (client) {
        client.remoteUsers.forEach(function (user) {
          if (user.audioTrack) {
            try { user.audioTrack.play(); } catch (_) {}
          }
        });
      }
      audioUnlockButton.remove();
      audioUnlockButton = null;
    });
    document.body.appendChild(audioUnlockButton);
  }

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
      window.AgoraRTC.onAudioAutoplayFailed = showAudioUnlock;
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
