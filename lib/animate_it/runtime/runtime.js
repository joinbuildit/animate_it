// AnimateIt client runtime: plays a recorded track document against a
// once-rendered scene DOM.
(function (global) {
  "use strict";

  var Easing = {
    linear: function (p) { return p; },
    ease_in: function (p) { return p * p; },
    ease_out: function (p) { return 1 - (1 - p) * (1 - p); },
    ease_in_out: function (p) {
      if (p < 0.5) return 2 * p * p;
      var q = -2 * p + 2;
      return 1 - (q * q) / 2;
    }
  };

  function round4(value) {
    var rounded = Math.round(Math.abs(value) * 1e4) / 1e4;
    return value < 0 ? -rounded : rounded;
  }

  function formatComputed(value) {
    return Number.isInteger(value) ? value.toFixed(1) : String(value);
  }

  function interpolate(input, frames, values, easingName) {
    var n = frames.length;
    if (input < frames[0]) return { raw: values[0] };
    if (input > frames[n - 1]) return { raw: values[n - 1] };

    var left = 0;
    if (input > frames[0]) {
      left = -1;
      for (var i = 0; i < n - 1; i += 1) {
        if (input >= frames[i] && input <= frames[i + 1]) { left = i; break; }
      }
      if (left === -1) left = n - 2;
    }

    var start = frames[left];
    var end = frames[left + 1];
    if (end === start) return { raw: values[left] };

    var progress = (input - start) / (end - start);
    var eased = (Easing[easingName] || Easing.ease_out)(progress);
    return { computed: values[left] + (values[left + 1] - values[left]) * eased };
  }

  function compileTrack(track) {
    if (track.t === "rle") {
      var expanded = [];
      for (var i = 0; i < track.r.length; i += 1) {
        var value = track.r[i][0];
        for (var j = 0; j < track.r[i][1]; j += 1) expanded.push(value);
      }
      return {
        valueAt: function (frame) {
          if (!expanded.length) return "";
          return expanded[Math.min(frame, expanded.length - 1)];
        }
      };
    }

    var frames = track.k.map(function (pair) { return pair[0]; });
    var values = track.k.map(function (pair) { return pair[1]; });
    var unit = track.u || "";
    var easing = track.e || "ease_out";
    return {
      valueAt: function (frame) {
        var result = interpolate(frame, frames, values, easing);
        if ("raw" in result) return String(result.raw) + unit;
        return formatComputed(round4(result.computed)) + unit;
      }
    };
  }

  // Pause native CSS/Web Animations and seek them to deterministic frame
  // time. Layers use scene-local time so delayed scenes start at zero.
  var animationCache = typeof WeakMap === "undefined" ? null : new WeakMap();

  function seekAnimations(root, frame, fps) {
    if (!root || typeof root.getAnimations !== "function") return [];

    var frameRate = Number(fps);
    if (!(frameRate > 0)) return [];

    var currentTime = (frame / frameRate) * 1000;
    var animations = Array.prototype.slice.call(root.getAnimations({ subtree: true }));
    var cached = animationCache && animationCache.get(root);
    if (cached) {
      cached.forEach(function (animation) {
        if (animation.playState !== "idle" && animations.indexOf(animation) === -1) animations.push(animation);
      });
    }
    animations.forEach(function (animation) {
      animation.pause();
      animation.currentTime = currentTime;
    });
    if (animationCache) animationCache.set(root, animations);
    return animations;
  }

  function createPlayer(doc, root) {
    var duration = doc.duration;
    var varBindings = [];
    var group;
    var name;

    for (group in doc.groups || {}) {
      var groupSelector = (doc.groupSelectors || {})[group] || '[data-animate-vars="' + group + '"]';
      var els = root.querySelectorAll(groupSelector);
      if (!els.length) continue;
      for (name in doc.groups[group]) {
        varBindings.push({
          els: els,
          name: name,
          track: compileTrack(doc.groups[group][name]),
          last: null,
          initialized: false
        });
      }
    }

    var textBindings = [];
    for (name in doc.texts || {}) {
      var textSelector = (doc.textSelectors || {})[name] || '[data-animate-text="' + name + '"]';
      var textEls = root.querySelectorAll(textSelector);
      if (!textEls.length) continue;
      textBindings.push({ els: textEls, track: compileTrack(doc.texts[name]), last: null });
    }

    var layers = (doc.layers || []).map(function (layer) {
      return {
        els: root.querySelectorAll(layer.sel),
        from: layer.from,
        to: layer.to,
        origin: Number(layer.origin) || 0,
        active: null
      };
    });

    var current = -1;

    function setFrame(n) {
      var frame = Math.max(0, Math.min(duration - 1, Math.round(Number(n) || 0)));
      current = frame;

      layers.forEach(function (layer) {
        var active = frame >= layer.from && frame < layer.to;
        if (active === layer.active) return;
        layer.active = active;
        layer.els.forEach(function (el) { el.classList.toggle("is-active", active); });
      });

      varBindings.forEach(function (binding) {
        var value = binding.track.valueAt(frame);
        if (binding.initialized && value === binding.last) return;
        binding.initialized = true;
        binding.last = value;
        binding.els.forEach(function (el) {
          if (value === null) el.style.removeProperty(binding.name);
          else el.style.setProperty(binding.name, value);
        });
      });

      textBindings.forEach(function (binding) {
        var value = binding.track.valueAt(frame);
        if (value === binding.last) return;
        binding.last = value;
        binding.els.forEach(function (el) { el.textContent = value; });
      });

      if (layers.length) {
        layers.forEach(function (layer) {
          if (!layer.active) return;
          layer.els.forEach(function (el) {
            seekAnimations(el, frame - layer.origin, doc.fps);
          });
        });
      } else {
        seekAnimations(root, frame, doc.fps);
      }
      return frame;
    }

    return {
      duration: duration,
      fps: doc.fps,
      setFrame: setFrame,
      currentFrame: function () { return current; }
    };
  }

  // Owns wall-clock playback for production embeds. Audio starts only from
  // this transport, so a browser-blocked autoplay attempt falls back to the
  // visible Play control instead of silently advancing the picture.
  function createTransport(player, audios, options) {
    var settings = options || {};
    var shouldLoop = settings.loop !== false;
    var button = settings.button || null;
    var duration = player.duration;
    var fps = player.fps;
    var frame = player.currentFrame() < 0 ? 0 : player.currentFrame();
    var animationFrame = null;
    var startedAt = 0;
    var startedFrame = frame;

    audios.forEach(function (el) {
      var gain = Number(el.dataset.gain);
      if (Number.isFinite(gain)) el.volume = Math.max(0, Math.min(1, gain));
      el.loop = el.dataset.loop === "true";
    });

    function audioWindow(el) {
      var start = Number(el.dataset.fromFrame) || 0;
      var rawLength = Number(el.dataset.durationFrames);
      return { start: start, length: rawLength > 0 ? rawLength : duration - start };
    }

    function audioTime(el, localTime) {
      if (el.dataset.loop !== "true" || !Number.isFinite(el.duration) || el.duration <= 0) return localTime;
      return localTime % el.duration;
    }

    function updateButton(playing) {
      if (!button) return;
      button.textContent = playing ? "Pause" : "Play";
      button.setAttribute("aria-pressed", playing ? "true" : "false");
    }

    function prepareAudio(el, currentFrame, shouldPlay) {
      var window = audioWindow(el);
      var within = currentFrame >= window.start && currentFrame < window.start + window.length;
      if (!within) {
        if (!el.paused) el.pause();
        return Promise.resolve();
      }

      var begin = function () {
        var time = audioTime(el, (currentFrame - window.start) / fps);
        if (!shouldPlay || el.paused) el.currentTime = time;
        if (!shouldPlay) {
          if (!el.paused) el.pause();
          return Promise.resolve();
        }
        if (!el.paused) return Promise.resolve();
        return Promise.resolve(el.play());
      };

      if (el.readyState >= 1) return begin();
      return new Promise(function (resolve, reject) {
        el.addEventListener("loadedmetadata", function () {
          begin().then(resolve, reject);
        }, { once: true });
        el.addEventListener("error", function () {
          reject(new Error("AnimateIt audio failed to load"));
        }, { once: true });
      });
    }

    function syncAudio(currentFrame, shouldPlay) {
      return Promise.all(audios.map(function (el) {
        return prepareAudio(el, currentFrame, shouldPlay);
      }));
    }

    function stopAudio() {
      audios.forEach(function (el) { if (!el.paused) el.pause(); });
    }

    function pause() {
      if (animationFrame !== null) global.cancelAnimationFrame(animationFrame);
      animationFrame = null;
      syncAudio(frame, false);
      updateButton(false);
    }

    function seek(nextFrame) {
      frame = player.setFrame(nextFrame);
      if (animationFrame !== null) {
        stopAudio();
        startedAt = global.performance.now();
        startedFrame = frame;
        syncAudio(frame, true).catch(pause);
      } else {
        syncAudio(frame, false);
      }
      return frame;
    }

    function tick(now) {
      if (animationFrame === null) return;
      var next = startedFrame + Math.floor(((now - startedAt) / 1000) * fps);
      if (next >= duration) {
        if (!shouldLoop) {
          frame = player.setFrame(duration - 1);
          pause();
          return;
        }
        frame = player.setFrame(0);
        stopAudio();
        startedAt = now;
        startedFrame = 0;
        syncAudio(frame, true).catch(pause);
      } else if (next !== frame) {
        frame = player.setFrame(next);
        syncAudio(frame, true).catch(pause);
      }
      if (animationFrame !== null) animationFrame = global.requestAnimationFrame(tick);
    }

    function play() {
      if (animationFrame !== null) return Promise.resolve();
      if (frame >= duration - 1) frame = player.setFrame(0);
      startedAt = global.performance.now();
      startedFrame = frame;
      updateButton(true);
      animationFrame = global.requestAnimationFrame(tick);
      return syncAudio(frame, true).catch(function (error) {
        pause();
        throw error;
      });
    }

    function toggle() {
      return animationFrame === null ? play() : (pause(), Promise.resolve());
    }

    if (button) button.addEventListener("click", function () { toggle().catch(function () {}); });
    updateButton(false);

    return {
      play: play,
      pause: pause,
      toggle: toggle,
      seek: seek,
      playing: function () { return animationFrame !== null; },
      currentFrame: function () { return frame; }
    };
  }

  function boot() {
    var script = document.querySelector("script[data-animate-it-tracks]");
    if (!script) return;
    var player = createPlayer(JSON.parse(script.textContent), document);
    player.setFrame(0);
    global.__animateIt = { totalFrames: player.duration, setFrame: player.setFrame };
    global.AnimateItRuntime = player;
    if (script.dataset.animateItTransport === "true") {
      var transport = createTransport(
        player,
        Array.prototype.slice.call(document.querySelectorAll("audio[data-from-frame]")),
        {
          loop: script.dataset.animateItLoop === "true",
          button: document.querySelector("[data-animate-it-play]")
        }
      );
      global.AnimateItTransport = transport;
      if (script.dataset.animateItAutoplay === "true") transport.play().catch(function () {});
    }
    document.documentElement.dataset.animateItReady = "1";
  }

  var api = {
    Easing: Easing,
    round4: round4,
    formatComputed: formatComputed,
    interpolate: interpolate,
    compileTrack: compileTrack,
    seekAnimations: seekAnimations,
    createPlayer: createPlayer,
    createTransport: createTransport
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    global.AnimateItRuntimeApi = api;
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", boot);
    } else {
      boot();
    }
  }
})(typeof window !== "undefined" ? window : globalThis);
