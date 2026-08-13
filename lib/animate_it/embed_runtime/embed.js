(function (global) {
  "use strict";

  if (!global.customElements || global.customElements.get("animate-it-embed")) return;

  function clamp(value, min, max) { return Math.max(min, Math.min(max, value)); }

  class AnimateItEmbed extends HTMLElement {
    connectedCallback() {
      if (this.connected) return;
      this.connected = true;
      this.manifest = JSON.parse(this.querySelector("[data-animate-it-embed-manifest]").textContent);
      this.options = this.manifest.options;
      this.viewport = this.querySelector("[data-animate-it-embed-viewport]");
      this.frame = this.querySelector("[data-animate-it-embed-frame]");
      this.control = this.querySelector("[data-animate-it-embed-control]");
      this.chapterControls = Array.from(this.querySelectorAll("[data-animate-it-chapter]"));
      this.reducedMotion = global.matchMedia("(prefers-reduced-motion: reduce)");
      this.userPaused = false;
      this.userStarted = this.options.autoplay;
      this.visibleRatio = 0;
      this.playerReady = false;
      this.currentChapter = null;
      this.playing = false;
      this.boundMessage = this.receiveMessage.bind(this);
      this.boundVisibility = this.syncPlayback.bind(this);
      this.boundVariantChange = this.variantChanged.bind(this);
      this.boundReducedMotion = this.reducedMotionChanged.bind(this);
      this.boundControl = this.toggle.bind(this);
      this.boundResize = this.scaleFrame.bind(this);
      global.addEventListener("message", this.boundMessage);
      document.addEventListener("visibilitychange", this.boundVisibility);
      this.control.addEventListener("click", this.boundControl);
      this.reducedMotion.addEventListener("change", this.boundReducedMotion);
      this.chapterControls.forEach((control) => {
        control.addEventListener("click", () => this.seekChapter(control.dataset.animateItChapter));
      });
      if ("ResizeObserver" in global) {
        this.resizeObserver = new global.ResizeObserver(this.boundResize);
        this.resizeObserver.observe(this.viewport);
      } else {
        global.addEventListener("resize", this.boundResize);
      }
      this.setupVariants();
      this.setupVisibility();
      this.applyReducedMotion();
    }

    disconnectedCallback() {
      global.removeEventListener("message", this.boundMessage);
      document.removeEventListener("visibilitychange", this.boundVisibility);
      this.control && this.control.removeEventListener("click", this.boundControl);
      this.reducedMotion && this.reducedMotion.removeEventListener("change", this.boundReducedMotion);
      this.resizeObserver && this.resizeObserver.disconnect();
      global.removeEventListener("resize", this.boundResize);
      this.intersectionObserver && this.intersectionObserver.disconnect();
      (this.variantQueries || []).forEach((entry) => entry.query.removeEventListener("change", this.boundVariantChange));
      this.cancelLoad();
      this.clearReadyTimer();
      this.removePlayer();
      this.connected = false;
    }

    setupVariants() {
      this.variantQueries = this.manifest.variants.filter((variant) => variant.media).map((variant) => ({
        variant: variant,
        query: global.matchMedia(variant.media)
      }));
      this.variantQueries.forEach((entry) => entry.query.addEventListener("change", this.boundVariantChange));
      this.activateVariant(this.selectedVariant());
    }

    selectedVariant() {
      const matched = this.variantQueries.find((entry) => entry.query.matches);
      return matched ? matched.variant : this.manifest.variants[0];
    }

    variantChanged() {
      const variant = this.selectedVariant();
      if (this.variant && variant.source === this.variant.source) return;
      this.activateVariant(variant);
    }

    activateVariant(variant) {
      const resumeChapter = this.currentChapter;
      this.cancelLoad();
      this.clearReadyTimer();
      this.removePlayer();
      this.variant = variant;
      this.resumeChapter = resumeChapter;
      this.playerReady = false;
      this.dataset.playerReady = "false";
      const composition = variant.composition;
      this.style.setProperty("--animate-it-crossfade-duration", `${this.options.crossfadeDuration}ms`);
      this.viewport.style.aspectRatio = `${composition.width} / ${composition.height}`;
      this.scaleFrame();
      this.updateChapters(0, null);
      if (!this.reducedMotion.matches && this.visibleRatio >= this.options.loadWhenVisible) this.scheduleLoad();
    }

    setupVisibility() {
      if (!global.IntersectionObserver) {
        this.visibleRatio = 1;
        if (!this.reducedMotion.matches) this.scheduleLoad();
        return;
      }
      const thresholds = Array.from(new Set([0, this.options.loadWhenVisible, this.options.playWhenVisible, 1])).sort();
      this.intersectionObserver = new IntersectionObserver((entries) => {
        const entry = entries[entries.length - 1];
        this.visibleRatio = entry && entry.isIntersecting && entry.boundingClientRect.height > 0 ?
          entry.intersectionRect.height / entry.boundingClientRect.height : 0;
        if (this.visibleRatio >= this.options.loadWhenVisible && !this.iframe && !this.reducedMotion.matches) this.scheduleLoad();
        this.syncPlayback();
      }, { threshold: thresholds });
      this.intersectionObserver.observe(this.viewport);
    }

    applyReducedMotion() {
      this.dataset.reducedMotion = this.reducedMotion.matches ? "true" : "false";
      if (this.reducedMotion.matches) {
        this.cancelLoad();
        this.removePlayer();
      }
    }

    reducedMotionChanged() {
      this.applyReducedMotion();
      if (!this.reducedMotion.matches && this.visibleRatio >= this.options.loadWhenVisible) this.scheduleLoad();
    }

    scheduleLoad() {
      if (this.iframe || this.loadHandle) return;
      const load = () => {
        this.loadHandle = null;
        if (!this.reducedMotion.matches && this.visibleRatio >= this.options.loadWhenVisible) this.mountPlayer();
      };
      if ("requestIdleCallback" in global) this.loadHandle = global.requestIdleCallback(load, { timeout: 800 });
      else this.loadHandle = global.setTimeout(load, 0);
    }

    cancelLoad() {
      if (!this.loadHandle) return;
      if ("cancelIdleCallback" in global) global.cancelIdleCallback(this.loadHandle);
      else global.clearTimeout(this.loadHandle);
      this.loadHandle = null;
    }

    mountPlayer() {
      if (this.iframe) return;
      const composition = this.variant.composition;
      const separator = this.variant.source.includes("?") ? "&" : "?";
      const iframe = document.createElement("iframe");
      iframe.src = `${this.variant.source}${separator}embedded=1&host_navigation=${this.chapterControls.length ? "1" : "0"}`;
      iframe.title = this.manifest.title;
      iframe.loading = "eager";
      iframe.tabIndex = -1;
      iframe.setAttribute("aria-hidden", "true");
      iframe.setAttribute("allow", "autoplay");
      iframe.width = composition.width;
      iframe.height = composition.height;
      iframe.addEventListener("load", () => {
        if (iframe !== this.iframe) return;
        if (!iframe.contentDocument || !iframe.contentDocument.querySelector("[data-animate-it-tracks]")) {
          this.fail(new Error("AnimateIt player returned an invalid document"));
          return;
        }
        this.readyTimer = global.setTimeout(() => this.degradedReady(), this.options.readyTimeout);
      }, { once: true });
      iframe.addEventListener("error", () => this.fail(new Error("AnimateIt player failed to load")), { once: true });
      this.iframe = iframe;
      this.frame.replaceChildren(iframe);
      this.scaleFrame();
    }

    removePlayer() {
      if (this.iframe) {
        this.send("pause");
        this.iframe.remove();
      }
      this.iframe = null;
      this.playerReady = false;
      this.playing = false;
      if (this.control) this.control.hidden = true;
    }

    scaleFrame() {
      if (!this.variant || !this.viewport) return;
      const composition = this.variant.composition;
      const scale = this.viewport.clientWidth / composition.width;
      this.frame.style.width = `${composition.width}px`;
      this.frame.style.height = `${composition.height}px`;
      this.frame.style.transform = `scale(${scale})`;
    }

    receiveMessage(event) {
      if (!this.iframe || event.source !== this.iframe.contentWindow || event.origin !== global.location.origin) return;
      const message = event.data || {};
      if (message.namespace !== "animate-it" || !message.event) return;
      const detail = message.detail || {};
      if (message.event === "ready") this.ready(detail);
      else if (message.event === "framechange") this.frameChanged(detail);
      else if (message.event === "chapterchange") this.chapterChanged(detail);
      else if (message.event === "play") this.setPlaying(true);
      else if (message.event === "pause" || message.event === "ended") this.setPlaying(false);
      else if (message.event === "error") this.fail(new Error(detail.message || "AnimateIt player error"));
      this.dispatchEvent(new CustomEvent(`animateit:${message.event}`, { detail }));
    }

    ready(detail) {
      this.clearReadyTimer();
      this.playerReady = true;
      this.dataset.playerReady = "true";
      this.dataset.playerReadiness = "complete";
      this.control.hidden = false;
      if (this.resumeChapter) this.send("seekChapter", { chapter: this.resumeChapter });
      this.updateChapters(detail.frame || 0, detail.chapter);
      this.syncPlayback();
    }

    degradedReady() {
      if (!this.iframe || this.playerReady) return;
      this.playerReady = true;
      this.dataset.playerReady = "true";
      this.dataset.playerReadiness = "degraded";
      this.control.hidden = false;
      this.syncPlayback();
      this.dispatchEvent(new CustomEvent("animateit:degradedready"));
    }

    fail(error) {
      this.clearReadyTimer();
      this.dataset.playerReady = "false";
      this.dataset.playerError = "true";
      this.playerReady = false;
      this.control.hidden = true;
      this.dispatchEvent(new CustomEvent("animateit:error", { detail: { message: error.message } }));
    }

    clearReadyTimer() {
      if (this.readyTimer) global.clearTimeout(this.readyTimer);
      this.readyTimer = null;
    }

    frameChanged(detail) {
      this.lastFrame = Number(detail.frame) || 0;
      this.updateChapters(this.lastFrame, detail.chapter);
    }

    chapterChanged(detail) {
      this.currentChapter = detail.chapter || null;
      this.updateChapters(Number(detail.frame) || 0, this.currentChapter);
    }

    updateChapters(frame, namedChapter) {
      const chapters = this.variant.composition.chapters;
      let currentIndex = -1;
      for (let index = chapters.length - 1; index >= 0; index -= 1) {
        if (frame >= chapters[index].startFrame) { currentIndex = index; break; }
      }
      if (namedChapter) currentIndex = chapters.findIndex((chapter) => chapter.name === namedChapter);
      const current = currentIndex >= 0 ? chapters[currentIndex] : null;
      this.currentChapter = current && current.name;
      const progress = current ? (current.durationFrames === 1 ? 1 :
        clamp((frame - current.startFrame) / (current.durationFrames - 1), 0, 1)) : 0;
      this.chapterControls.forEach((control) => {
        const index = chapters.findIndex((chapter) => chapter.name === control.dataset.animateItChapter);
        const state = currentIndex < 0 || index > currentIndex ? "upcoming" : (index < currentIndex ? "completed" : "current");
        const position = currentIndex < 0 ? "hidden" :
          (index === currentIndex ? "current" : (index === currentIndex - 1 ? "previous" : (index === currentIndex + 1 ? "next" : "hidden")));
        control.dataset.chapterState = state;
        control.dataset.chapterPosition = position;
        control.style.setProperty("--animate-it-chapter-progress", String(state === "completed" ? 1 : (state === "current" ? progress : 0)));
        control.style.setProperty("--animate-it-chapter-active", state === "current" ? "1" : "0");
        control.style.setProperty("--animate-it-chapter-complete", state === "completed" ? "1" : "0");
        if (state === "current") control.setAttribute("aria-current", "step");
        else control.removeAttribute("aria-current");
      });
    }

    seekChapter(name) {
      if (!this.playerReady) { this.resumeChapter = name; return; }
      this.send("seekChapter", { chapter: name });
    }

    seek(frame) {
      this.send("seek", { frame: Number(frame) || 0 });
    }

    play() {
      this.userStarted = true;
      this.userPaused = false;
      this.send("play");
    }

    pause() {
      this.userPaused = true;
      this.send("pause");
    }

    playingState() {
      return this.playing;
    }

    currentFrame() {
      return this.lastFrame || 0;
    }

    toggle() {
      if (!this.playerReady) return;
      this.userStarted = true;
      this.userPaused = this.playing;
      this.send(this.playing ? "pause" : "play");
    }

    syncPlayback() {
      if (!this.playerReady) return;
      const inViewport = this.visibleRatio >= this.options.playWhenVisible;
      const shouldPlay = this.userStarted && !this.userPaused && !document.hidden &&
        (inViewport || !this.options.pauseOffscreen);
      if (shouldPlay && !this.playing) this.send("play");
      else if (!shouldPlay && this.playing) this.send("pause");
    }

    send(command, detail) {
      if (!this.iframe || !this.iframe.contentWindow) return;
      this.iframe.contentWindow.postMessage(Object.assign({ namespace: "animate-it", command }, detail || {}), global.location.origin);
    }

    setPlaying(playing) {
      this.playing = playing;
      this.control.textContent = playing ? "Pause" : "Play";
      this.control.setAttribute("aria-label", playing ? "Pause animation" : "Play animation");
      this.control.setAttribute("aria-pressed", playing ? "true" : "false");
    }
  }

  global.customElements.define("animate-it-embed", AnimateItEmbed);
})(typeof window !== "undefined" ? window : globalThis);
