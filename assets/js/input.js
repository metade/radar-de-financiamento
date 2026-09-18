import "@awesome.me/webawesome/dist/components/option/option.js";
import "@awesome.me/webawesome/dist/components/select/select.js";
import "@awesome.me/webawesome/dist/styles/themes/default.css";

const setupPromptCopy = () => {
  const button = document.querySelector("#copiar-prompt");
  const prompt = document.querySelector("#prompt-ia");
  const status = document.querySelector("#estado-copia-prompt");

  if (!button || !prompt || !status) return;

  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(prompt.textContent);
      button.textContent = "Copiado!";
      status.textContent = "Prompt copiado para o clipboard.";
      window.setTimeout(() => {
        button.textContent = "Copiar prompt";
        status.textContent = "";
      }, 1800);
    } catch {
      status.textContent = "Não foi possível copiar automaticamente. Selecione e copie o prompt manualmente.";
    }
  });
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupPromptCopy);
} else {
  setupPromptCopy();
}
