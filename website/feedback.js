// The form opens the visitor's mail app: there's no server, so nothing leaves until they send it.
(() => {
  const LINKEDIN = "https://www.linkedin.com/in/atayugrum/";

  const mailLink = document.querySelector("#mail-link");
  const address = `${mailLink.dataset.user}@${mailLink.dataset.domain}`;
  mailLink.textContent = address;
  mailLink.href = `mailto:${address}`;

  const linkedin = document.querySelector("#linkedin-link");
  if (LINKEDIN) {
    linkedin.href = LINKEDIN;
    linkedin.hidden = false;
  }

  const copy = document.querySelector("#copy-mail");
  let resetCopy;
  copy.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(address);
      copy.textContent = window.t("feedback.copied");
      clearTimeout(resetCopy);
      resetCopy = setTimeout(() => { copy.textContent = window.t("feedback.copy"); }, 1600);
    } catch {
      location.href = mailLink.href;
    }
  });

  const form = document.querySelector("#feedback-form");
  const error = form.querySelector(".fb-error");
  form.addEventListener("input", () => { error.hidden = true; });
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(form);
    const message = String(data.get("message")).trim();
    if (!message) {
      error.hidden = false;
      form.elements.message.focus();
      return;
    }
    const subject = `NotchOne: ${window.t(`feedback.${data.get("kind")}`)}`;
    location.href = `mailto:${address}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(message)}`;
  });
})();
