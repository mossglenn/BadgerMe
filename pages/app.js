/* BadgerMe — the only script on the site.
   Its whole job is to assemble the contact address at runtime, so a plain
   string never sits in the HTML for low-effort scrapers to grab.

   ┌─────────────────────────────────────────────────────────────┐
   │  EDIT THESE TWO LINES with your real support address.         │
   │  Use a dedicated, app-specific address (not your personal     │
   │  inbox) so you can forward or burn it if it ever gets spammed.│
   └─────────────────────────────────────────────────────────────┘ */
const CONTACT_USER   = "support";       // <-- the part before the @
const CONTACT_DOMAIN = "badgerme.app";  // <-- the part after the @
const CONTACT_SUBJECT = "BadgerMe";     // pre-filled email subject

(function () {
  const addr = CONTACT_USER + "@" + CONTACT_DOMAIN;

  function reveal(el) {
    const out = document.querySelector(el.getAttribute("data-target"));
    const href = "mailto:" + addr + "?subject=" + encodeURIComponent(CONTACT_SUBJECT);
    if (out) {
      out.innerHTML = "";
      const a = document.createElement("a");
      a.href = href;
      a.textContent = addr;
      out.appendChild(a);
    } else {
      window.location.href = href;
    }
    el.textContent = "Opening your mail app…";
    el.disabled = true;
  }

  document.querySelectorAll("[data-reveal-email]").forEach(function (btn) {
    btn.addEventListener("click", function () { reveal(btn); });
  });
})();
