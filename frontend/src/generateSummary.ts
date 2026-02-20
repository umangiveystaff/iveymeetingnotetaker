import { runOllama } from "./ollamaClient";
import templates from "./config/summary_templates.json";

type Template = {
  id: string;
  name: string;
  format: "json" | "markdown";
  prompt: string;
};

export async function generateSummaryFromTranscript(
  transcriptText: string,
  templateId: string,
  model = "llama3.2"
) {
  const template = (templates as Template[]).find((t) => t.id === templateId);
  if (!template) throw new Error("Invalid template selected");

  const prompt = `
You are an AI assistant analyzing a meeting transcript.

TRANSCRIPT (speaker-labeled where possible):
${transcriptText}

TASK:
${template.prompt}
  `.trim();

  const raw = await runOllama(model, prompt, template.format);

  if (template.format === "json") {
    try {
      return JSON.parse(raw);
    } catch {
      // Salvage valid JSON if the model added stray characters
      const fixed = raw.trim().replace(/^[^\[]*/, "").replace(/[^\]]*$/, "");
      return JSON.parse(fixed);
    }
  }

  return raw; // markdown string
}
