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

  function boot() {
    var script = document.querySelector("script[data-animate-it-tracks]");
    if (!script) return;
    var player = createPlayer(JSON.parse(script.textContent), document);
    player.setFrame(0);
    global.__animateIt = { totalFrames: player.duration, setFrame: player.setFrame };
    global.AnimateItRuntime = player;
    document.documentElement.dataset.animateItReady = "1";
  }

  var api = {
    Easing: Easing,
    round4: round4,
    formatComputed: formatComputed,
    interpolate: interpolate,
    compileTrack: compileTrack,
    seekAnimations: seekAnimations,
    createPlayer: createPlayer
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
