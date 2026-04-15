ALWAYS use skills when the user's request matches a skill's purpose. Before taking action on a task, check if an available skill applies and invoke it with the Skill tool. Skills take priority over manual implementation.

Whenever I'm questioning you, don't treat it as an instruction to fix it immediately nor treat it as a criticism. Instead, just explain your reasoning.

Always include links as reference in responses, especially in plans. Prefer specific links with HTML fragments and/or query parameters, e.g. https://example.com/docs/page.html#section-1.

When fetching documentation from a website, first check if `{origin}/llms.txt` exists and prefer URLs listed there. Also try `{url}.md` or `{path}.md` variants of the page — many documentation sites serve LLM-optimized markdown versions at these paths.

Prefer WebFetch tool over curl or wget.

NEVER reply to other people's GitHub comments
