/* MWeb Lite's own CommonMark/GFM extensions. Third-party libraries retain their licenses. */
(() => {
  "use strict";
  const content = document.getElementById("content");
  // WebKit on macOS renders its scrollbars outside the public NSView hierarchy.
  // Keep its native scrolling and add only the visible, interactive overlay.
  function makeScrollbar(target, vertical) {
    const root = target === document.documentElement;
    const track = document.createElement("div");
    const thumb = document.createElement("div");
    track.className = `preview-scrollbar ${vertical ? "vertical" : "horizontal"}`;
    thumb.className = "preview-scrollbar-thumb";
    track.append(thumb);
    track.tabIndex = 0;
    track.setAttribute("role", "scrollbar");
    track.setAttribute("aria-label", vertical ? "滚动文章" : "横向滚动内容");
    track.setAttribute("aria-orientation", vertical ? "vertical" : "horizontal");
    track.setAttribute("aria-valuemin", "0");
    track.setAttribute("aria-controls", target.id || "content");
    document.body.append(track);
    let timer, drag = null, geometry = null;
    const source = () => root ? document.scrollingElement : target;
    const value = () => vertical ? source().scrollTop : source().scrollLeft;
    const setValue = (position) => source().scrollTo(vertical
      ? { top: position, behavior: "instant" } : { left: position, behavior: "instant" });
    const show = () => {
      track.classList.add("active");
      clearTimeout(timer);
      timer = setTimeout(() => track.classList.remove("active"), 900);
    };
    const update = () => {
      const element = source();
      const rect = root ? { left: 0, top: 0, right: innerWidth, bottom: innerHeight }
        : target.getBoundingClientRect();
      const extent = vertical ? element.scrollHeight : element.scrollWidth;
      const viewport = vertical ? (root ? innerHeight : target.clientHeight) : target.clientWidth;
      const start = vertical ? 2 : Math.max(0, rect.left) + 2;
      const end = vertical ? innerHeight - 2 : Math.min(innerWidth, rect.right) - 2;
      const length = Math.max(0, end - start);
      const maximum = Math.max(0, extent - viewport);
      const thumbLength = Math.min(length, Math.max(24, length * viewport / extent));
      const travel = length - thumbLength;
      geometry = { start, maximum, thumbLength, travel };
      track.hidden = maximum < 1 || length < 1 || (!root &&
        (rect.bottom <= 0 || rect.bottom > innerHeight || rect.right <= 0 || rect.left >= innerWidth));
      if (vertical) {
        track.style.top = `${start}px`;
        track.style.height = `${length}px`;
        thumb.style.height = `${thumbLength}px`;
        thumb.style.transform = `translateY(${maximum ? Math.max(0, Math.min(maximum, value())) / maximum * travel : 0}px)`;
      } else {
        track.style.left = `${start}px`;
        track.style.top = `${rect.bottom - 10}px`;
        track.style.width = `${length}px`;
        thumb.style.width = `${thumbLength}px`;
        thumb.style.transform = `translateX(${maximum ? Math.max(0, Math.min(maximum, value())) / maximum * travel : 0}px)`;
      }
      track.setAttribute("aria-valuemax", String(Math.round(maximum)));
      track.setAttribute("aria-valuenow", String(Math.round(value())));
    };
    const coordinate = (event) => vertical ? event.clientY : event.clientX;
    const move = (event) => {
      if (!drag || drag.id !== event.pointerId || !geometry?.travel) return;
      setValue((coordinate(event) - geometry.start - drag.grip) / geometry.travel * geometry.maximum);
      update();
      show();
    };
    const stop = () => {
      const previous = drag;
      drag = null;
      if (previous && track.hasPointerCapture(previous.id)) track.releasePointerCapture(previous.id);
      track.classList.remove("dragging");
      show();
    };
    track.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      update();
      const rect = thumb.getBoundingClientRect();
      drag = { id: event.pointerId, grip: event.target === thumb
        ? coordinate(event) - (vertical ? rect.top : rect.left) : geometry.thumbLength / 2 };
      track.classList.add("dragging");
      // Synthetic integration-test events have no active pointer to capture.
      if (event.isTrusted) track.setPointerCapture(event.pointerId);
      move(event);
    });
    track.addEventListener("pointermove", move);
    track.addEventListener("pointerup", stop);
    track.addEventListener("pointercancel", stop);
    track.addEventListener("lostpointercapture", stop);
    track.addEventListener("pointerenter", show);
    track.addEventListener("keydown", (event) => {
      const step = vertical ? innerHeight : target.clientWidth;
      const delta = { ArrowUp: -40, ArrowLeft: -40, ArrowDown: 40, ArrowRight: 40,
        PageUp: -step, PageDown: step }[event.key];
      if (delta === undefined && !["Home", "End"].includes(event.key)) return;
      event.preventDefault();
      setValue(event.key === "Home" ? 0 : event.key === "End" ? geometry.maximum : value() + delta);
      show();
    });
    const onScroll = () => { update(); show(); };
    (root ? window : target).addEventListener("scroll", onScroll, { passive: true });
    return { update, stop, destroy() {
      clearTimeout(timer);
      (root ? window : target).removeEventListener("scroll", onScroll);
      track.remove();
    } };
  }

  const pageScrollbar = makeScrollbar(document.documentElement, true);
  const horizontalScrollbars = new Map();
  let scrollbarFrame = null;
  function scheduleScrollbars() {
    if (scrollbarFrame !== null) return;
    scrollbarFrame = requestAnimationFrame(() => {
      scrollbarFrame = null;
      pageScrollbar.update();
      for (const [element, scrollbar] of horizontalScrollbars) {
        if (element.isConnected) scrollbar.update();
        else { scrollbar.destroy(); horizontalScrollbars.delete(element); scrollbarResizeObserver.unobserve(element); }
      }
      for (const element of content.querySelectorAll("pre, table, .math-display, .diagram")) {
        if (!horizontalScrollbars.has(element)) {
          const scrollbar = makeScrollbar(element, false);
          horizontalScrollbars.set(element, scrollbar);
          scrollbarResizeObserver.observe(element);
          scrollbar.update();
        }
      }
    });
  }
  const scrollbarResizeObserver = new ResizeObserver(scheduleScrollbars);
  scrollbarResizeObserver.observe(content);
  new MutationObserver(scheduleScrollbars).observe(content, { childList: true, subtree: true, characterData: true });
  content.addEventListener("load", scheduleScrollbars, true);
  addEventListener("resize", scheduleScrollbars);
  addEventListener("scroll", scheduleScrollbars, { passive: true });
  scheduleScrollbars();
  const escapeHTML = (text) => String(text).replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character]));
  const md = window.markdownit({ html: true, linkify: true, typographer: false, breaks: false })
    .use(window.markdownitFootnote)
    .use(window.markdownitTaskLists, { enabled: false, label: false });

  // MWeb accepts both double-backtick math and dollar-delimited math.
  md.inline.ruler.before("escape", "mweb_math", (state, silent) => {
    const start = state.pos;
    if (state.src[start] !== "$" || (start > 0 && state.src[start - 1] === "\\")) return false;
    const delimiter = state.src[start + 1] === "$" ? "$$" : "$";
    const from = start + delimiter.length;
    if (delimiter === "$" && /\s/.test(state.src[from] || "")) return false;
    let end = state.src.indexOf(delimiter, from);
    while (end > 0 && state.src[end - 1] === "\\") end = state.src.indexOf(delimiter, end + delimiter.length);
    if (end < 0 || end === from || (delimiter === "$" && /\s/.test(state.src[end - 1]))) return false;
    if (delimiter === "$" && /^\d/.test(state.src.slice(end + 1))) return false;
    if (!silent) {
      const token = state.push("mweb_math", "", 0);
      token.content = state.src.slice(from, end);
      token.block = delimiter === "$$";
    }
    state.pos = end + delimiter.length;
    return true;
  });
  md.block.ruler.before("fence", "mweb_math_block", (state, startLine, endLine, silent) => {
    const start = state.bMarks[startLine] + state.tShift[startLine];
    const first = state.src.slice(start, state.eMarks[startLine]).trim();
    if (!first.startsWith("$$")) return false;
    let text = first.slice(2), nextLine = startLine;
    if (text.endsWith("$$")) text = text.slice(0, -2);
    else {
      let closed = false;
      for (nextLine = startLine + 1; nextLine < endLine; nextLine++) {
        const line = state.src.slice(state.bMarks[nextLine] + state.tShift[nextLine], state.eMarks[nextLine]);
        if (line.trimEnd().endsWith("$$")) { text += "\n" + line.trimEnd().slice(0, -2); closed = true; break; }
        text += "\n" + line;
      }
      if (!closed) return false;
    }
    if (silent) return true;
    const token = state.push("mweb_math", "", 0);
    token.block = true;
    token.content = text.trim();
    token.map = [startLine, nextLine + 1];
    state.line = nextLine + 1;
    return true;
  });
  const mathHTML = (text, block) => block
    ? `<div class="math-display">\\[${escapeHTML(text)}\\]</div>\n`
    : `<span class="math-inline">\\(${escapeHTML(text)}\\)</span>`;
  md.renderer.rules.mweb_math = (tokens, index) => mathHTML(tokens[index].content, tokens[index].block);
  const normalInlineCode = md.renderer.rules.code_inline;
  md.renderer.rules.code_inline = (tokens, index, options, env, renderer) => tokens[index].markup === "``"
    ? mathHTML(tokens[index].content, false)
    : normalInlineCode(tokens, index, options, env, renderer);

  const normalFence = md.renderer.rules.fence;
  md.renderer.rules.fence = (tokens, index, options, env, renderer) => {
    const token = tokens[index], language = token.info.trim().split(/\s+/)[0].toLowerCase();
    if (["math", "latex", "tex"].includes(language)) return mathHTML(token.content, true);
    if (["mermaid", "echarts"].includes(language)) {
      return `<div class="diagram" data-kind="${language}"><pre><code>${escapeHTML(token.content)}</code></pre></div>\n`;
    }
    return normalFence(tokens, index, options, env, renderer);
  };

  const normalImage = md.renderer.rules.image;
  md.renderer.rules.image = (tokens, index, options, env, renderer) => {
    const token = tokens[index];
    const alt = renderer.renderInlineAsText(token.children || [], options, env);
    const width = alt.match(/-w(\d+)(?:\s|$)/);
    let result = normalImage(tokens, index, options, env, renderer);
    if (width) {
      result = result.replace(/alt="[^"]*"/, `alt="${escapeHTML(alt.replace(width[0], ""))}"`)
        .replace("<img ", `<img width="${Math.min(10000, Number(width[1]))}" `);
    }
    return result;
  };
  md.core.ruler.push("mweb_headings", (state) => {
    const counts = new Map();
    state.env.headings = [];
    for (let index = 0; index < state.tokens.length; index++) {
      const token = state.tokens[index];
      if (token.type !== "heading_open") continue;
      const inline = state.tokens[index + 1];
      const title = (inline.children || []).filter((item) => ["text", "code_inline"].includes(item.type)).map((item) => item.content).join("");
      const base = title.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").trim().replace(/\s+/g, "-") || "section";
      const count = counts.get(base) || 0;
      counts.set(base, count + 1);
      const id = count ? `${base}-${count}` : base;
      token.attrSet("id", id);
      state.env.headings.push({ id, title, level: Number(token.tag.slice(1)) });
    }
  });

  const loading = new Map();
  function loadRuntime(path) {
    if (loading.has(path)) return loading.get(path);
    const promise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "mweblite://runtime/" + path;
      script.onload = resolve;
      script.onerror = reject;
      document.head.append(script);
    });
    loading.set(path, promise);
    return promise;
  }

  function rewriteURLs(baseURL) {
    for (const element of content.querySelectorAll("[src], [href], [poster]")) {
      for (const attribute of ["src", "href", "poster"]) {
        if (!element.hasAttribute(attribute)) continue;
        const value = element.getAttribute(attribute);
        if (attribute === "href" && value.startsWith("#")) continue;
        try {
          const url = new URL(value, baseURL);
          const protocols = attribute === "href" ? ["https:", "http:", "mailto:", "mweblib:", "mweb:", "mweblite:"] : ["https:", "http:", "mweblite:", "data:"];
          if (!protocols.includes(url.protocol) || (url.protocol === "mweblite:" && url.host !== "library")) element.removeAttribute(attribute);
          else element.setAttribute(attribute, url.href);
        } catch { element.removeAttribute(attribute); }
      }
      element.removeAttribute("srcset");
      element.removeAttribute("target");
    }
  }

  function safeChartOptions(value) {
    if (!value || typeof value !== "object") return;
    for (const [key, item] of Object.entries(value)) {
      if (["__proto__", "constructor", "prototype"].includes(key)) { delete value[key]; continue; }
      if (["link", "sublink"].includes(key) && typeof item === "string" && !/^https?:\/\//i.test(item)) value[key] = "";
      if (key === "tooltip" && item && typeof item === "object") item.renderMode = "richText";
      safeChartOptions(item);
    }
  }

  let revision = 0;
  let charts = [];
  let mathQueue = Promise.resolve();
  async function enhance(renderRevision, runtimeAvailable) {
    const current = () => revision === renderRevision;
    const diagrams = Array.from(content.querySelectorAll(".diagram"));
    if (!runtimeAvailable) {
      for (const diagram of diagrams) {
        const note = document.createElement("p"); note.className = "render-note";
        note.textContent = "安装 MWeb 后可使用本机的图表渲染资源。"; diagram.append(note);
      }
      return;
    }
    if (content.querySelector("pre code[class*='language-']")) {
      loadRuntime("prism/prism.js").then(() => { if (current() && window.Prism) window.Prism.highlightAllUnder(content); }).catch(() => {});
    }
    if (content.querySelector(".math-inline, .math-display")) {
      // Serialize MathJax; it keeps a document-wide typesetting state.
      mathQueue = mathQueue.catch(() => {}).then(async () => {
        if (!window.MathJax) window.MathJax = {
          loader: { load: ["ui/safe"] },
          tex: { inlineMath: [["\\(", "\\)"]], displayMath: [["\\[", "\\]"]], packages: { "[-]": ["autoload", "require"] } },
          options: { enableMenu: false }, startup: { typeset: false }
        };
        await loadRuntime("mathjax/tex-svg-full.js");
        if (!current()) return;
        await window.MathJax.startup.promise;
        if (!current()) return;
        window.MathJax.typesetClear?.([content]);
        await window.MathJax.typesetPromise([content]);
      }).catch(() => {});
    }
    for (const diagram of diagrams) {
      const kind = diagram.dataset.kind;
      const code = diagram.querySelector("code")?.textContent || "";
      try {
        if (kind === "mermaid") {
          await loadRuntime("mermaid/mermaid.10.2.4.min.js");
          if (!current()) return;
          window.mermaid.initialize({ startOnLoad: false, securityLevel: "strict", htmlLabels: false,
            flowchart: { htmlLabels: false }, theme: matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default" });
          const result = await window.mermaid.render(`diagram-${renderRevision}-${diagrams.indexOf(diagram)}`, code);
          if (current()) diagram.innerHTML = window.DOMPurify.sanitize(result.svg, { USE_PROFILES: { html: true, svg: true, svgFilters: true }, ADD_TAGS: ["foreignObject"], ADD_ATTR: ["dominant-baseline"] });
        } else if (kind === "echarts") {
          await loadRuntime("echarts/echarts.min.js");
          if (!current()) return;
          const options = window.JSON5.parse(code.trim().replace(/^(?:var\s+|let\s+|const\s+)?option\s*=\s*/, "").replace(/;\s*$/, ""));
          safeChartOptions(options);
          diagram.textContent = ""; diagram.classList.add("chart");
          const chart = window.echarts.init(diagram, null, { renderer: "canvas" });
          chart.setOption(options); charts.push(chart);
        }
      } catch {
        if (!current()) return;
        const note = document.createElement("p"); note.className = "render-note";
        note.textContent = "图表未能渲染，已保留源代码。ECharts 仅接受数据配置。";
        diagram.replaceChildren();
        const pre = document.createElement("pre"); const codeElement = document.createElement("code");
        codeElement.textContent = code; pre.append(codeElement); diagram.append(pre, note);
      }
    }
  }

  window.renderMarkdown = (source, baseURL, runtimeAvailable, resetScroll) => {
    const renderRevision = ++revision;
    if (resetScroll) pageScrollbar.stop();
    const oldY = resetScroll ? 0 : window.scrollY;
    for (const chart of charts) chart.dispose();
    charts = [];
    const env = {};
    let rendered = md.render(source, env);
    const minimumLevel = Math.min(...env.headings.map((heading) => heading.level), 6);
    const toc = '<nav class="table-of-contents" aria-label="目录"><ul>' + env.headings.map((heading) =>
      `<li style="padding-left:${(heading.level - minimumLevel) * 16}px"><a href="#${escapeHTML(heading.id)}">${escapeHTML(heading.title)}</a></li>`
    ).join("") + "</ul></nav>";
    rendered = rendered.replace(/<p>\[TOC\]<\/p>/gi, toc);
    content.innerHTML = window.DOMPurify.sanitize(rendered, {
      USE_PROFILES: { html: true },
      FORBID_TAGS: ["style", "form", "iframe", "object", "embed", "base", "meta", "link"],
      FORBID_ATTR: ["style", "srcset", "formaction", "autofocus", "autoplay"],
      ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|mweblib|mweb|mweblite):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i
    });
    rewriteURLs(baseURL);
    // TOC indentation is applied after sanitization, so note-supplied CSS stays disabled.
    content.querySelectorAll(".table-of-contents li").forEach((item, index) => { if (env.headings[index]) item.style.paddingLeft = `${(env.headings[index].level - minimumLevel) * 16}px`; });
    window.scrollTo({ left: 0, top: oldY, behavior: "instant" });
    if (resetScroll) {
      // A document switch cancels any old smooth TOC scroll and settles at the
      // new layout's origin. Never let an older render move a newer article.
      requestAnimationFrame(() => {
        if (revision === renderRevision) window.scrollTo({ left: 0, top: 0, behavior: "instant" });
      });
    }
    enhance(renderRevision, runtimeAvailable);
    scheduleScrollbars();
  };

  document.addEventListener("click", (event) => {
    const anchor = event.target.closest("a[href^='#']");
    if (!anchor) return;
    event.preventDefault();
    const id = decodeURIComponent(anchor.getAttribute("href").slice(1));
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
  });
  addEventListener("resize", () => charts.forEach((chart) => chart.resize()));
})();
