// Winston Everywhere: inject banner instead of redirecting

// Listen for completed navigation in main frame
browser.webNavigation.onCompleted.addListener(async function(details) {
  try {
    if (details.frameId !== 0) return; // only main frame
    const urlStr = details.url;
    if (!urlStr) return;

    let url;
    try {
      url = new URL(urlStr);
    } catch (e) {
      console.error('[WinstonEverywhere] Invalid URL:', urlStr, e);
      return;
    }

    // Only act on reddit
    if (!url.hostname.includes('reddit.com')) return;

    console.log('[WinstonEverywhere] Page completed on reddit:', urlStr);

    // Build Winston URL preserving path and query
    const winstonUrl = `https://app.winston.cafe${url.pathname}${url.search}`;

    // Inject banner content script
    try {
      await browser.tabs.executeScript(details.tabId, {
        code: `
          (function() {
            try {
              if (document.getElementById('winston-open-banner')) return; // already added

              const banner = document.createElement('div');
              banner.id = 'winston-open-banner';
              banner.setAttribute('role', 'region');
              banner.setAttribute('aria-label', 'Open in Winston');
              banner.style.position = 'fixed';
              banner.style.top = '0';
              banner.style.left = '0';
              banner.style.right = '0';
              banner.style.zIndex = '2147483647';
              banner.style.display = 'flex';
              banner.style.justifyContent = 'space-between';
              banner.style.alignItems = 'center';
              banner.style.padding = '10px 14px';
              banner.style.background = 'linear-gradient(90deg, #111827, #1f2937)';
              banner.style.color = '#ffffff';
              banner.style.fontFamily = '-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif';
              banner.style.fontSize = '14px';
              banner.style.boxShadow = '0 2px 8px rgba(0,0,0,0.25)';

              const text = document.createElement('span');
              text.textContent = 'Open this post in Winston';
              text.style.marginRight = '12px';

              const link = document.createElement('a');
              link.href = ${JSON.stringify(winstonUrl)};
              link.textContent = 'Open in Winston';
              link.style.background = '#2563eb';
              link.style.color = '#fff';
              link.style.padding = '8px 12px';
              link.style.borderRadius = '6px';
              link.style.textDecoration = 'none';
              link.style.fontWeight = '600';
              link.style.marginLeft = '8px';
              link.target = '_blank';
              link.rel = 'noopener noreferrer';

              const left = document.createElement('div');
              left.style.display = 'flex';
              left.style.alignItems = 'center';
              left.appendChild(text);
              left.appendChild(link);

              const close = document.createElement('button');
              close.type = 'button';
              close.setAttribute('aria-label', 'Dismiss banner');
              close.textContent = '×';
              close.style.background = 'transparent';
              close.style.border = 'none';
              close.style.color = '#fff';
              close.style.fontSize = '20px';
              close.style.cursor = 'pointer';
              close.style.marginLeft = '12px';

              close.addEventListener('click', function() {
                banner.remove();
              });

              banner.appendChild(left);
              banner.appendChild(close);

              document.documentElement.appendChild(banner);

              // Push content down so it doesn't get hidden under fixed headers
              const spacer = document.createElement('div');
              spacer.id = 'winston-open-banner-spacer';
              spacer.style.height = '48px';
              spacer.style.width = '100%';
              spacer.style.pointerEvents = 'none';
              document.body.prepend(spacer);

            } catch (err) {
              console.error('[WinstonEverywhere] Failed to inject banner:', err);
            }
          })();
        `
      });
    } catch (injectErr) {
      console.error('[WinstonEverywhere] executeScript error:', injectErr);
    }
  } catch (outerErr) {
    console.error('[WinstonEverywhere] Unexpected error:', outerErr);
  }
});

// Cleanup: ensure old redirect listener is not used
try {
  if (typeof listener !== 'undefined' && listener) {
    browser.webNavigation.onBeforeNavigate.removeListener(listener);
  }
} catch (e) {
  // ignore
}
