import type { Plugin } from "@opencode-ai/plugin";

// Advisory plugin: watches for edits to service files and reminds the session
// to update documentation. Non-blocking — emits a toast notice only.
// Mirrors the .cursor/hooks/flag-doc-drift.sh advisory for opencode sessions.

const INFRA_PATHS = [/^apps\/base\//, /^base\/services\//];

const DOC_PATHS = [
  /^README\.md$/,
  /^CLAUDE\.md$/,
  /^docs\/adr\//,
  /^docs\//,
];

function extractService(path: string): string | null {
  const appsMatch = path.match(/^apps\/base\/([^/]+)\//);
  if (appsMatch) return appsMatch[1];
  const svcMatch = path.match(/^base\/services\/([^/]+)\.ya?ml$/);
  if (svcMatch) return svcMatch[1];
  return null;
}

const DocGuardPlugin: Plugin = async (_ctx) => {
  const touchedServices = new Set<string>();
  let docsTouched = false;

  return {
    event: async ({ event }) => {
      if (event.type === "file.edited") {
        const path: string = (event.properties as { path?: string }).path ?? "";

        if (DOC_PATHS.some((re) => re.test(path))) {
          docsTouched = true;
          touchedServices.clear();
          return;
        }

        if (INFRA_PATHS.some((re) => re.test(path))) {
          const svc = extractService(path);
          if (svc && !docsTouched) {
            touchedServices.add(svc);
          }
        }
      }

      // On session idle (agent finished a turn), remind if services were changed without docs
      if (event.type === "session.idle" && touchedServices.size > 0 && !docsTouched) {
        const list = [...touchedServices].join(", ");
        console.warn(
          `[doc-guard] Services modified without a doc update: ${list}. ` +
            "Update README.md, docs/adr/, or CLAUDE.md before pushing. " +
            "Run 'make docs-draft' for AI-drafted suggestions."
        );
      }
    },
  };
};

export default DocGuardPlugin;
