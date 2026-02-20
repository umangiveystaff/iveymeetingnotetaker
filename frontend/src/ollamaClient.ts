export async function runOllama(
  model: string,
  prompt: string,
  format: "json" | "markdown" = "markdown"
) {
  const body: any = { model, prompt, stream: false };
  if (format === "json") body.format = "json";

  const res = await fetch("http://127.0.0.1:11434/api/generate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Ollama error ${res.status}: ${text}`);
  }

  const data = await res.json();
  return data.response as string;
}
