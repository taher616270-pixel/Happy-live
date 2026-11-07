(function () {
  "use strict";

  let client = null;
  let localAudioTrack = null;
  let joining = false;
  let audioUnlockButton = null;
  let audioEventsRegistered = false;
  const remoteAudioTracks = new Map();

  function removeAudioUnlock() {
    if (!audioUnlockButton) return;
    audioUnlockButton.remove();
    audioUnlockButton = null;
  }

  function registerAudioEvents() {
    if (audioEventsRegistered || !window.AgoraRTC) return;
    audioEventsRegistered = true;
    window.AgoraRTC.on("autoplay-failed", showAudioUnlock);
    window.AgoraRTC.on("audio-context-state-changed", function (state) {
      console.info("[HappyLive Agora] audio context", state);
      if (state === "interrupted" || state === "suspended") {
        showAudioUnlock();
      } else if (state === "running") {
        removeAudioUnlock();
        playRemoteAudio();
      }
    });
  }

  function playRemoteAudio() {
    if (!client) return;
    client.remoteUsers.forEach(function (user) {
      if (!user.audioTrack) return;
      try {
        const result = user.audioTrack.play();
        if (result && typeof result.catch === "function") {
          result.catch(function (error) {
            console.warn("[HappyLive Agora] remote audio playback blocked", error);
            showAudioUnlock();
          });
        }
      } catch (error) {
        console.warn("[HappyLive Agora] remote audio playback failed", error);
        showAudioUnlock();
      }
    });
  }

  function showAudioUnlock() {
    if (audioUnlockButton || !document.body) return;
    audioUnlockButton = document.createElement("button");
    audioUnlockButton.type = "button";
    audioUnlockButton.textContent = "اضغط لتفعيل صوت الغرفة";
    audioUnlockButton.setAttribute("aria-label", "تفعيل صوت الغرفة");
    audioUnlockButton.style.cssText = "position:fixed;z-index:2147483647;left:50%;bottom:26px;transform:translateX(-50%);padding:13px 20px;border:1px solid rgba(232,196,119,.7);border-radius:24px;background:linear-gradient(110deg,#3a2948,#17131f);color:#fff;font:700 14px system-ui;box-shadow:0 8px 28px #0008";
    audioUnlockButton.addEventListener("click", async function () {
      try {
        if (window.AgoraRTC && typeof window.AgoraRTC.resumeAudioContext === "function") {
          await window.AgoraRTC.resumeAudioContext();
        }
        playRemoteAudio();
        removeAudioUnlock();
      } catch (error) {
        console.warn("[HappyLive Agora] audio context resume failed", error);
        showAudioUnlock();
      }
    });
    document.body.appendChild(audioUnlockButton);
  }

  async function leaveCurrent() {
    remoteAudioTracks.clear();
    if (localAudioTrack) {
      try { localAudioTrack.stop(); localAudioTrack.close(); } catch (_) {}
      localAudioTrack = null;
    }
    if (client) {
      const oldClient = client;
      client = null;
      try { await oldClient.leave(); } catch (error) {
        console.warn("[HappyLive Agora] leave failed", error);
      }
    }
  }

  async function join(appId, channel, token, uid, publish) {
    if (!window.AgoraRTC) throw new Error("تعذر تحميل مكتبة Agora");
    if (joining) throw new Error("اتصال الصوت قيد التجهيز");
    joining = true;
    try {
      await leaveCurrent();
      const nextClient = window.AgoraRTC.createClient({ mode: "live", codec: "vp8" });
      client = nextClient;

      registerAudioEvents();

      nextClient.on("user-published", async function (user, mediaType) {
        try {
          await nextClient.subscribe(user, mediaType);
          if (mediaType === "audio" && user.audioTrack) {
            remoteAudioTracks.set(String(user.uid), user.audioTrack);
            const playback = user.audioTrack.play();
            if (playback && typeof playback.catch === "function") {
              playback.catch(function (error) {
                console.warn("[HappyLive Agora] autoplay blocked", error);
                showAudioUnlock();
              });
            }
          }
        } catch (error) {
          console.error("[HappyLive Agora] subscribe failed", error);
        }
      });

      nextClient.on("user-unpublished", function (user, mediaType) {
        if (mediaType === "audio") remoteAudioTracks.delete(String(user.uid));
      });

      nextClient.on("connection-state-change", function (current, previous, reason) {
        console.info("[HappyLive Agora] connection", previous, "->", current, reason || "");
      });

      // Keep lightweight diagnostics so intermittent network degradation can
      // be distinguished from browser audio playback interruptions.
      nextClient.on("network-quality", function (stats) {
        const qualityNames = {
          0: "unknown", 1: "excellent", 2: "good", 3: "slightly-impaired",
          4: "not-smooth", 5: "very-poor", 6: "disconnected"
        };
        const uplink = Number(stats.uplinkNetworkQuality);
        const downlink = Number(stats.downlinkNetworkQuality);
        console.info("[HappyLive Agora] local network quality", {
          uplink,
          uplinkLabel: qualityNames[uplink] || "unknown",
          downlink,
          downlinkLabel: qualityNames[downlink] || "unknown"
        });
        try {
          const remoteQuality = nextClient.getRemoteNetworkQuality();
          if (remoteQuality && Object.keys(remoteQuality).length) {
            console.info("[HappyLive Agora] remote network quality", remoteQuality);
          }
        } catch (error) {
          console.debug("[HappyLive Agora] remote network quality unavailable", error);
        }
      });
      nextClient.on("exception", function (event) {
        console.warn("[HappyLive Agora] media exception", event);
      });

      // Set the role before joining so the server-issued co-host privileges
      // and the client role are aligned from the start of the session.
      await nextClient.setClientRole(publish ? "host" : "audience");
      await nextClient.join(appId, channel, token, Number(uid));

      if (publish) {
        localAudioTrack = await window.AgoraRTC.createMicrophoneAudioTrack({
          // Voice-room speech profile: mono 32 kHz / 24 Kbps instead of the
          // default music profile, reducing uplink bandwidth per speaker.
          encoderConfig: "speech_standard",
          AEC: true,
          ANS: true,
          AGC: true
        });
        await nextClient.publish([localAudioTrack]);
      }

      // A participant may already be publishing when this client joins.
      for (const user of nextClient.remoteUsers) {
        if (user.hasAudio) {
          try {
            await nextClient.subscribe(user, "audio");
            if (user.audioTrack) {
              remoteAudioTracks.set(String(user.uid), user.audioTrack);
              user.audioTrack.play();
            }
          } catch (error) {
            console.warn("[HappyLive Agora] initial audio subscribe failed", error);
          }
        }
      }
      return true;
    } catch (error) {
      console.error("[HappyLive Agora] join failed", error);
      await leaveCurrent();
      throw error;
    } finally {
      joining = false;
    }
  }

  async function setMuted(muted) {
    if (!localAudioTrack) return false;
    try {
      await localAudioTrack.setEnabled(!muted);
      return true;
    } catch (error) {
      console.warn("[HappyLive Agora] microphone mute change failed", error);
      return false;
    }
  }

  window.happyLiveAgora = {
    join: join,
    leave: leaveCurrent,
    setMuted: setMuted,
    resumeAudio: async function () {
      if (window.AgoraRTC && typeof window.AgoraRTC.resumeAudioContext === "function") {
        await window.AgoraRTC.resumeAudioContext();
      }
      playRemoteAudio();
      return true;
    },
    isLoaded: function () { return !!window.AgoraRTC; },
    getVersion: function () { return window.AgoraRTC ? window.AgoraRTC.VERSION : null; }
  };
})();
