import { existsSync, readFileSync } from "node:fs";

const MANIFEST_FILE = "../app-update-manifest.json";

const parseVersion = (version) => version.split(".").map((segment) => Number(segment) || 0);

const compareVersion = (left, right) => {
  const a = parseVersion(left);
  const b = parseVersion(right);
  const max = Math.max(a.length, b.length);
  for (let index = 0; index < max; index += 1) {
    const diff = (a[index] || 0) - (b[index] || 0);
    if (diff !== 0) return diff;
  }
  return 0;
};

const defaultManifest = {
  appName: "ZyroAi",
  currentVersion: "1.0.0",
  latestVersion: "1.0.0",
  channel: "stable",
  source: "local-manifest",
  updateAvailable: false,
  mandatory: false,
  downloadUrl: "",
  releaseNotes: [
    "Executive command center refresh",
    "Live event stream for workspace updates",
    "Expanded planner, memory, habit, and communication features"
  ]
};

const readLocalManifest = () => {
  if (!existsSync(MANIFEST_FILE)) {
    return defaultManifest;
  }

  return { ...defaultManifest, ...JSON.parse(readFileSync(MANIFEST_FILE, "utf8")) };
};

export const loadUpdateManifest = async (clientVersion) => {
  const configuredUrl = process.env.GITHUB_UPDATE_MANIFEST_URL;
  if (!configuredUrl) {
    const local = readLocalManifest();
    const currentVersion = clientVersion || local.currentVersion;
    return {
      ...local,
      currentVersion,
      updateAvailable: compareVersion(local.latestVersion, currentVersion) > 0
    };
  }

  try {
    const response = await fetch(configuredUrl, { signal: AbortSignal.timeout(4000) });
    if (!response.ok) {
      throw new Error(`Manifest fetch failed with ${response.status}`);
    }
    const remote = await response.json();
    const merged = { ...defaultManifest, ...remote, source: "remote-manifest" };
    const currentVersion = clientVersion || merged.currentVersion;
    return {
      ...merged,
      currentVersion,
      updateAvailable: compareVersion(merged.latestVersion, currentVersion) > 0
    };
  } catch {
    const local = readLocalManifest();
    const currentVersion = clientVersion || local.currentVersion;
    return {
      ...local,
      currentVersion,
      source: "remote-manifest-fallback",
      updateAvailable: compareVersion(local.latestVersion, currentVersion) > 0
    };
  }
};
