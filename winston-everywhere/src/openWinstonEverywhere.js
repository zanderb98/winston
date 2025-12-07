"use strict";

// Winston Everywhere (Content Script): inject banner directly on reddit pages
(function() {
  const LOG_PREFIX = '[WinstonEverywhere]';

  function isRedditHost(hostname) {
    return typeof hostname === 'string' && hostname.includes('reddit.com');
  }
    
  function isSubredditSubmitPage(location) {
    const path = location.pathname;
    const regex = /^\/r\/[^\/]+\/submit\/?$/;
    return regex.test(path);
  }

  function buildWinstonUrl(loc) {
    try {
      const url = new URL(loc.href);
      return `winstonapp://${url.pathname.startsWith('/') ? url.pathname.slice(1) : url.pathname}${url.search}`;
    } catch (e) {
      console.error(LOG_PREFIX, 'Failed to build Winston URL from location:', loc && loc.href, e);
      return null;
    }
  }

  function injectBannerIfNeeded() {
    try {
      const { location } = window;
      if (!location || !isRedditHost(location.hostname) || isSubredditSubmitPage(location)) {
        removeBannerIfPresent();
        return;
      }

      const existing = document.getElementById('winston-open-banner');
      const winstonUrl = buildWinstonUrl(location);
      if (!winstonUrl) return;

      if (existing) {
        const link = existing.querySelector('a#winston-open-link');
        if (link) link.href = winstonUrl;
        return;
      }

      // Create banner with improved styling
      const banner = document.createElement('div');
      banner.id = 'winston-open-banner';
      banner.setAttribute('role', 'region');
      banner.setAttribute('aria-label', 'Open in Winston');
      banner.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        z-index: 2147483647;
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 12px 20px;
        background: linear-gradient(135deg, #1a1a1a 0%, #2d1410 100%);
        color: #ffffff;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        font-size: 14px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15), 0 1px 3px rgba(0, 0, 0, 0.2);
        backdrop-filter: blur(10px);
        border-bottom: 1px solid rgba(255, 98, 78, 0.2);
        transition: transform 0.3s ease;
      `;

      const close = document.createElement('button');
      close.type = 'button';
      close.setAttribute('aria-label', 'Dismiss banner');
      close.textContent = '✕';
      close.style.cssText = `
        background: transparent;
        border: none;
        color: #FF624E;
        font-size: 24px;
        cursor: pointer;
        margin-right: 16px;
        padding: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        -webkit-tap-highlight-color: transparent;
        line-height: 1;
      `;

      close.addEventListener('click', function() {
        banner.style.transform = 'translateY(-100%)';
        setTimeout(() => removeBannerIfPresent(), 300);
      });

      const text = document.createElement('span');
      text.textContent = 'Open in Winston';
      text.style.cssText = `
        font-weight: 600;
        letter-spacing: 0.3px;
        color: #e0e0e0;
        flex: 1;
      `;

      const link = document.createElement('a');
      link.id = 'winston-open-link';
      link.href = winstonUrl;
      link.textContent = '';
      link.style.cssText = `
        display: inline-flex;
        align-items: center;
        gap: 6px;
        background: #FF624E;
        color: #ffffff;
        padding: 8px 16px;
        border-radius: 8px;
        text-decoration: none;
        font-weight: 600;
        font-size: 14px;
        box-shadow: 0 2px 8px rgba(255, 98, 78, 0.4);
      `;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';

      const linkText = document.createElement('span');
      linkText.textContent = 'Open App';
      link.appendChild(linkText);

      const arrow = document.createElement('span');
      arrow.textContent = '→';
      arrow.setAttribute('aria-hidden', 'true');
      arrow.style.cssText = `
        display: inline-block;
        font-size: 14px;
      `;
      link.appendChild(arrow);

      banner.appendChild(close);
      banner.appendChild(text);
      banner.appendChild(link);

      document.documentElement.appendChild(banner);

      // Animate in
      requestAnimationFrame(() => {
        banner.style.transform = 'translateY(0)';
      });

      ensureSpacer();

      console.log(LOG_PREFIX, 'Banner injected on reddit:', window.location.href);
    } catch (err) {
      console.error(LOG_PREFIX, 'Failed to inject banner:', err);
    }
  }

  function ensureSpacer() {
    let spacer = document.getElementById('winston-open-banner-spacer');
    if (!spacer) {
      spacer = document.createElement('div');
      spacer.id = 'winston-open-banner-spacer';
      spacer.style.height = '52px';
      spacer.style.width = '100%';
      spacer.style.pointerEvents = 'none';
      if (document.body && document.body.firstChild) {
        document.body.insertBefore(spacer, document.body.firstChild);
      } else if (document.body) {
        document.body.appendChild(spacer);
      } else {
        document.addEventListener('DOMContentLoaded', () => ensureSpacer(), { once: true });
      }
    }
  }

  function removeBannerIfPresent() {
    const banner = document.getElementById('winston-open-banner');
    if (banner && banner.parentNode) banner.parentNode.removeChild(banner);
    const spacer = document.getElementById('winston-open-banner-spacer');
    if (spacer && spacer.parentNode) spacer.parentNode.removeChild(spacer);
  }

  function setupSpaNavigationWatcher() {
    let lastHref = location.href;

    function checkUrlChange() {
      if (location.href !== lastHref) {
        lastHref = location.href;
        injectBannerIfNeeded();
      }
    }

    const origPushState = history.pushState;
    const origReplaceState = history.replaceState;

    if (typeof origPushState === 'function') {
      history.pushState = function(...args) {
        const ret = origPushState.apply(this, args);
        setTimeout(checkUrlChange, 0);
        return ret;
      };
    }

    if (typeof origReplaceState === 'function') {
      history.replaceState = function(...args) {
        const ret = origReplaceState.apply(this, args);
        setTimeout(checkUrlChange, 0);
        return ret;
      };
    }

    window.addEventListener('popstate', () => setTimeout(checkUrlChange, 0));

    const observer = new MutationObserver(() => {
      checkUrlChange();
    });
    observer.observe(document.documentElement, { subtree: true, childList: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      injectBannerIfNeeded();
      setupSpaNavigationWatcher();
    });
  } else {
    injectBannerIfNeeded();
    setupSpaNavigationWatcher();
  }
})();
