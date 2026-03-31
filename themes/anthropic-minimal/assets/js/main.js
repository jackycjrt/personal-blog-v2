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
      // Ignore storage errors for private mode or blocked storage.
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

  function toggleTheme() {
    var current = document.documentElement.getAttribute("data-theme") || resolveTheme();
    var next = current === "dark" ? "light" : "dark";
    writeStoredTheme(next);
    applyTheme(next);
  }

  function bindThemeToggle() {
    var toggle = document.getElementById("themeToggle");
    if (!toggle) {
      return;
    }
    toggle.addEventListener("click", toggleTheme);
  }

  function bindHeaderScroll() {
    var header = document.getElementById("siteHeader");
    if (!header) {
      return;
    }

    var update = function () {
      if (window.scrollY > 8) {
        header.classList.add("is-scrolled");
      } else {
        header.classList.remove("is-scrolled");
      }
    };

    update();
    window.addEventListener("scroll", update, { passive: true });
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
      block.style.transitionDelay = (index * 45) + "ms";
      observer.observe(block);
    });
  }

  function observeSystemTheme() {
    var mql = window.matchMedia("(prefers-color-scheme: dark)");
    var handleChange = function (event) {
      var hasStored = readStoredTheme();
      if (hasStored !== "light" && hasStored !== "dark") {
        applyTheme(event.matches ? "dark" : "light");
      }
    };

    if (typeof mql.addEventListener === "function") {
      mql.addEventListener("change", handleChange);
    } else if (typeof mql.addListener === "function") {
      mql.addListener(handleChange);
    }
  }

  applyTheme(resolveTheme());
  bindThemeToggle();
  bindHeaderScroll();
  bindReveal();
  observeSystemTheme();
})();
