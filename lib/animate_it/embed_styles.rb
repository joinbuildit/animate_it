module AnimateIt
  module EmbedStyles
    module_function

    def chapter_source
      @chapter_source ||= <<~CSS.freeze
        .animate-it-chapters {
          --animate-it-progress-color: #28d2bc;
          --animate-it-progress-width: 2.5px;
          --animate-it-active-glow: 0 0 10px 2px rgb(40 210 188 / 42%);
          --animate-it-chapter-color: #414b57;
          --animate-it-chapter-background: #fff;
          --animate-it-chapter-shadow: 0 4px 12px rgb(39 47 57 / 8%);
          --animate-it-chapter-font: 700 14px/1 system-ui, sans-serif;
          --animate-it-chapter-gap: 14px;
          --animate-it-chapter-height: 44px;
          --animate-it-carousel-distance: 108%;
          --animate-it-carousel-scale: .84;
          --animate-it-carousel-opacity: .68;
          --animate-it-carousel-duration: 180ms;
          display: grid;
          grid-template-columns: repeat(var(--animate-it-chapter-count, 4), minmax(0, 1fr));
          gap: var(--animate-it-chapter-gap);
        }
        .animate-it-chapter--pills {
          --animate-it-chapter-progress: 0;
          --animate-it-chapter-active: 0;
          --animate-it-chapter-complete: 0;
          position: relative;
          min-width: 0;
          min-height: 44px;
          height: var(--animate-it-chapter-height);
          padding: 2px;
          border: 0;
          border-radius: 999px;
          appearance: none;
          color: var(--animate-it-chapter-color);
          background: var(--animate-it-chapter-background);
          box-shadow: var(--animate-it-chapter-shadow);
          cursor: pointer;
        }
        .animate-it-chapter--pills[data-chapter-state="current"] { box-shadow: var(--animate-it-active-glow); }
        .animate-it-chapter--pills:focus-visible { outline: 3px solid var(--animate-it-progress-color); outline-offset: 3px; }
        .animate-it-chapter__progress { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; pointer-events: none; }
        .animate-it-chapter__progress rect {
          fill: none;
          stroke: var(--animate-it-progress-color);
          stroke-width: var(--animate-it-progress-width);
          stroke-dasharray: var(--animate-it-chapter-progress) 1;
          stroke-opacity: clamp(0, calc(var(--animate-it-chapter-progress) * 1000), 1);
          stroke-linecap: round;
          vector-effect: non-scaling-stroke;
        }
        .animate-it-chapter__label {
          position: relative;
          display: flex;
          height: 100%;
          align-items: center;
          justify-content: center;
          opacity: calc(.58 + (var(--animate-it-chapter-active) * .42));
          font: var(--animate-it-chapter-font);
        }
        @media (max-width: 767px) {
          .animate-it-chapters--mobile-carousel { position: relative; display: block; height: var(--animate-it-chapter-height); overflow: clip; }
          .animate-it-chapters--mobile-carousel .animate-it-chapter--pills {
            position: absolute;
            left: 50%;
            width: min(31.25%, 122px);
            transition: transform var(--animate-it-carousel-duration) ease, opacity var(--animate-it-carousel-duration) ease;
          }
          .animate-it-chapters--mobile-carousel .animate-it-chapter--pills[data-chapter-position="previous"] { transform: translateX(calc(-50% - var(--animate-it-carousel-distance))) scale(var(--animate-it-carousel-scale)); opacity: var(--animate-it-carousel-opacity); }
          .animate-it-chapters--mobile-carousel .animate-it-chapter--pills[data-chapter-position="current"] { transform: translateX(-50%); opacity: 1; }
          .animate-it-chapters--mobile-carousel .animate-it-chapter--pills[data-chapter-position="next"] { transform: translateX(calc(-50% + var(--animate-it-carousel-distance))) scale(var(--animate-it-carousel-scale)); opacity: var(--animate-it-carousel-opacity); }
          .animate-it-chapters--mobile-carousel .animate-it-chapter--pills[data-chapter-position="hidden"] { visibility: hidden; pointer-events: none; opacity: 0; }
        }
        @media (prefers-reduced-motion: reduce) {
          .animate-it-chapter--pills { transition: none !important; }
        }
      CSS
    end

    def source
      @source ||= <<~CSS.freeze
        #{chapter_source}
        animate-it-embed {
          --animate-it-crossfade-duration: 120ms;
          position: relative;
          display: block;
          width: 100%;
          background: transparent;
        }
        .animate-it-embed__navigation { margin-bottom: 14px; }
        .animate-it-embed__viewport { position: relative; width: 100%; background: transparent; }
        .animate-it-embed__poster, .animate-it-embed__shell { position: absolute; inset: 0; width: 100%; height: 100%; }
        .animate-it-embed__poster { z-index: 2; margin: 0; opacity: 1; transition: opacity var(--animate-it-crossfade-duration) ease; pointer-events: none; }
        .animate-it-embed__poster img { display: block; width: 100%; height: 100%; object-fit: contain; }
        .animate-it-embed__shell { z-index: 1; overflow: hidden; opacity: 0; transition: opacity var(--animate-it-crossfade-duration) ease; background: transparent; }
        .animate-it-embed__frame { position: absolute; top: 0; left: 0; transform-origin: top left; background: transparent; }
        .animate-it-embed__frame iframe { display: block; border: 0; background: transparent; pointer-events: none; }
        animate-it-embed[data-player-ready="true"] .animate-it-embed__poster { opacity: 0; }
        animate-it-embed[data-player-ready="true"] .animate-it-embed__shell { opacity: 1; }
        .animate-it-embed__control {
          position: absolute;
          z-index: 4;
          right: 12px;
          bottom: 12px;
          width: 44px;
          height: 44px;
          padding: 0;
          border: 0;
          border-radius: 999px;
          color: #fff;
          background: rgb(18 24 29 / 84%);
          font: 700 13px/1 system-ui, sans-serif;
          cursor: pointer;
        }
        .animate-it-embed__control:focus-visible { outline: 3px solid var(--animate-it-progress-color, #28d2bc); outline-offset: 3px; }
        animate-it-embed[data-reduced-motion="true"] .animate-it-embed__navigation,
        animate-it-embed[data-reduced-motion="true"] .animate-it-embed__control { display: none; }
        @media (prefers-reduced-motion: reduce) {
          .animate-it-embed__poster, .animate-it-embed__shell { transition: none; }
        }
      CSS
    end
  end
end
