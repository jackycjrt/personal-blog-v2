(function () {
  function readStoredTheme() {
    try {
      return localStorage.getItem("theme");
    } catch (error) {
      return null;
    }
  }

  function writeStoredTheme(theme) {
    try {
      localStorage.setItem("theme", theme);
    } catch (error) {
      return null;
    }
  }

  function resolveTheme() {
    var stored = readStoredTheme();
    if (stored === "light" || stored === "dark") {
      return stored;
    }
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
  }

  function bindThemeToggle() {
    var button = document.getElementById("themeToggle");
    if (!button) {
      return;
    }

    button.addEventListener("click", function () {
      var current = document.documentElement.getAttribute("data-theme") || resolveTheme();
      var next = current === "dark" ? "light" : "dark";
      writeStoredTheme(next);
      applyTheme(next);
    });
  }

  function bindHeaderScroll() {
    var header = document.getElementById("siteHeader");
    if (!header) {
      return;
    }

    function update() {
      if (window.scrollY > 12) {
        header.classList.add("is-scrolled");
      } else {
        header.classList.remove("is-scrolled");
      }
    }

    update();
    window.addEventListener("scroll", update, { passive: true });
  }

  function bindReadingProgress() {
    var bar = document.getElementById("readingProgress");
    if (!bar) {
      return;
    }

    function update() {
      var scrollTop = window.scrollY || document.documentElement.scrollTop;
      var scrollHeight = document.documentElement.scrollHeight - window.innerHeight;
      var progress = scrollHeight > 0 ? (scrollTop / scrollHeight) * 100 : 0;
      bar.style.width = progress + "%";
    }

    update();
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
  }

  function bindReveal() {
    var blocks = document.querySelectorAll(".reveal");
    if (!blocks.length) {
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.08 });

    blocks.forEach(function (block, index) {
      block.style.transitionDelay = Math.min(index * 40, 240) + "ms";
      observer.observe(block);
    });
  }

  function observeSystemTheme() {
    var mql = window.matchMedia("(prefers-color-scheme: dark)");
    var listener = function (event) {
      var stored = readStoredTheme();
      if (stored !== "light" && stored !== "dark") {
        applyTheme(event.matches ? "dark" : "light");
      }
    };

    if (typeof mql.addEventListener === "function") {
      mql.addEventListener("change", listener);
    } else if (typeof mql.addListener === "function") {
      mql.addListener(listener);
    }
  }

  function bindAboutHero() {
    var hero = document.getElementById("aboutHeroTitle");
    var painting = document.getElementById("aboutPainting");
    var figure = document.getElementById("aboutHeroFigure");
    var stage = document.querySelector(".about-hero-stage");
    if (!hero || !painting || !figure || !stage) {
      return;
    }

    var ticking = false;

    function clamp(value, min, max) {
      return Math.min(Math.max(value, min), max);
    }

    function easeInOut(value) {
      return 0.5 - Math.cos(value * Math.PI) / 2;
    }

    function update() {
      var viewportHeight = window.innerHeight || document.documentElement.clientHeight;
      var stageHeight = Math.max(stage.offsetHeight, viewportHeight);
      var maxDistance = Math.max(stageHeight - viewportHeight * 0.18, 1);
      var rawProgress = clamp(window.scrollY / maxDistance, 0, 1);
      var easedProgress = easeInOut(rawProgress);

      var shiftX = easedProgress * Math.min(window.innerWidth * 0.22, 220);
      var shiftY = easedProgress * Math.min(viewportHeight * 0.24, 180);
      var scale = 1.06 - easedProgress * 0.15;
      var titleOpacity = 1 - easedProgress * 0.82;
      var titleBlur = easedProgress * 7.5;
      var uiOpacity = 1 - easedProgress * 0.55;
      var paintingOpacity = 0.08 + easedProgress * 0.3;
      var paintingDrift = 18 + (1 - easedProgress) * 28;
      var paintingScale = 1.06 - easedProgress * 0.03;
      var figureShiftY = easedProgress * Math.min(viewportHeight * 0.34, 260);
      var figureShiftX = easedProgress * Math.min(window.innerWidth * 0.06, 42);
      var figureScale = 1.04 - easedProgress * 0.1;
      var figureOpacity = 0.72 - easedProgress * 0.42;
      var figureBlur = easedProgress * 11.5;

      hero.style.setProperty("--about-hero-shift-x", shiftX.toFixed(2) + "px");
      hero.style.setProperty("--about-hero-shift-y", shiftY.toFixed(2) + "px");
      hero.style.setProperty("--about-hero-scale", scale.toFixed(3));
      hero.style.setProperty("--about-hero-opacity", titleOpacity.toFixed(3));
      hero.style.setProperty("--about-hero-blur", titleBlur.toFixed(2) + "px");

      stage.style.setProperty("--about-hero-ui-opacity", uiOpacity.toFixed(3));
      figure.style.setProperty("--about-hero-figure-shift-x", figureShiftX.toFixed(2) + "px");
      figure.style.setProperty("--about-hero-figure-shift-y", figureShiftY.toFixed(2) + "px");
      figure.style.setProperty("--about-hero-figure-scale", figureScale.toFixed(3));
      figure.style.setProperty("--about-hero-figure-opacity", figureOpacity.toFixed(3));
      figure.style.setProperty("--about-hero-figure-blur", figureBlur.toFixed(2) + "px");
      painting.style.opacity = paintingOpacity.toFixed(3);
      painting.style.transform =
        "scale(" + paintingScale.toFixed(3) + ") translate3d(0, " + paintingDrift.toFixed(2) + "px, 0)";
    }

    function requestTick() {
      if (ticking) {
        return;
      }
      ticking = true;
      window.requestAnimationFrame(function () {
        update();
        ticking = false;
      });
    }

    update();
    window.addEventListener("scroll", requestTick, { passive: true });
    window.addEventListener("resize", requestTick);
  }

  applyTheme(resolveTheme());
  bindThemeToggle();
  bindHeaderScroll();
  bindReadingProgress();
  bindReveal();
  observeSystemTheme();
  bindAboutHero();
})();
