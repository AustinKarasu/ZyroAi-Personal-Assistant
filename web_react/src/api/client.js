const browserHost = window.location.hostname || "127.0.0.1";
const apiHost = browserHost === "0.0.0.0" ? "127.0.0.1" : browserHost;
const API_BASE = `${window.location.protocol}//${apiHost}:8080/api`;
const DEVICE_KEY = "chief_device_id";
const WORKSPACE_CACHE_KEY = "zyroai_workspace_cache";
const storedDevice = localStorage.getItem(DEVICE_KEY);
const DEVICE_ID = storedDevice || `web-${crypto.randomUUID()}`;

if (!storedDevice) {
  localStorage.setItem(DEVICE_KEY, DEVICE_ID);
}

const headers = {
  "Content-Type": "application/json",
  "x-device-id": DEVICE_ID
};

async function parse(response, errorText) {
  if (!response.ok) {
    throw new Error(errorText);
  }
  return response.json();
}

async function request(path, options = {}, errorText = "Request failed") {
  return parse(
    await fetch(`${API_BASE}${path}`, {
      ...options,
      headers: {
        ...headers,
        ...(options.headers || {})
      }
    }),
    errorText
  );
}

export const chiefDeviceId = DEVICE_ID;


export async function clearLocalState() {
  localStorage.removeItem(WORKSPACE_CACHE_KEY);
  localStorage.removeItem(DEVICE_KEY);
  localStorage.removeItem('zyroai_installed_version');
  const keysToRemove = [];
  for (let index = 0; index < localStorage.length; index += 1) {
    const key = localStorage.key(index);
    if (key && key.startsWith('zyroai_update_dismissed_')) {
      keysToRemove.push(key);
    }
  }
  keysToRemove.forEach((key) => localStorage.removeItem(key));
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
  }
  if ('caches' in window) {
    const cacheKeys = await caches.keys();
    await Promise.all(cacheKeys.map((key) => caches.delete(key)));
  }
}

export function cacheWorkspace(workspace) {
  localStorage.setItem(WORKSPACE_CACHE_KEY, JSON.stringify({ cachedAt: new Date().toISOString(), workspace }));
}

export function readCachedWorkspace() {
  const raw = localStorage.getItem(WORKSPACE_CACHE_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw)?.workspace || null;
  } catch {
    return null;
  }
}

export function subscribeToWorkspace(onMessage) {
  const stream = new EventSource(`${API_BASE}/stream?deviceId=${encodeURIComponent(DEVICE_ID)}`);
  stream.onmessage = (event) => {
    const payload = JSON.parse(event.data);
    cacheWorkspace(payload);
    onMessage(payload);
  };
  stream.onerror = () => {
    stream.close();
  };
  return () => stream.close();
}

export async function fetchWorkspace() {
  try {
    const workspace = await request("/workspace", {}, "Workspace fetch failed");
    cacheWorkspace(workspace);
    return workspace;
  } catch (error) {
    const cached = readCachedWorkspace();
    if (cached) {
      return {
        ...cached,
        overview: {
          ...cached.overview,
          syncStatus: "Offline cache active"
        },
        offline: true
      };
    }
    throw error;
  }
}

export function fetchDashboard() {
  return request("/dashboard", {}, "Dashboard fetch failed");
}

export function addTask(payload) {
  return request(
    "/tasks",
    {
      method: "POST",
      body: JSON.stringify(payload)
    },
    "Task creation failed"
  );
}

export function updateTaskStatus(taskId, status) {
  return request(
    `/tasks/${taskId}/status`,
    {
      method: "PATCH",
      body: JSON.stringify({ status })
    },
    "Task update failed"
  );
}

export function decide(payload) {
  return request(
    "/decide",
    {
      method: "POST",
      body: JSON.stringify(payload)
    },
    "Decision request failed"
  );
}

export function addCallLog(caller, transcript) {
  return request(
    "/communications/call-log",
    {
      method: "POST",
      body: JSON.stringify({ caller, transcript })
    },
    "Call analysis failed"
  );
}

export function generateAutoReply(sender, context, until) {
  return request(
    "/messages/auto-reply",
    {
      method: "POST",
      body: JSON.stringify({ sender, context, until })
    },
    "Auto-reply failed"
  );
}

export function handleIncomingCall(caller, transcript) {
  return request(
    "/communications/incoming-call",
    {
      method: "POST",
      body: JSON.stringify({ caller, transcript })
    },
    "Incoming call handling failed"
  );
}

export function addMemory(hint, note) {
  return request(
    "/memory",
    {
      method: "POST",
      body: JSON.stringify({ hint, note })
    },
    "Memory save failed"
  );
}

export function addHabit(name) {
  return request(
    "/habits",
    {
      method: "POST",
      body: JSON.stringify({ name })
    },
    "Habit creation failed"
  );
}

export function checkInHabit(habitId) {
  return request(
    `/habits/${habitId}/check-in`,
    {
      method: "POST"
    },
    "Habit check-in failed"
  );
}

export function addMeeting(payload) {
  return request(
    "/meetings",
    {
      method: "POST",
      body: JSON.stringify(payload)
    },
    "Meeting creation failed"
  );
}

export function addContact(payload) {
  return request(
    "/contacts",
    {
      method: "POST",
      body: JSON.stringify(payload)
    },
    "Contact creation failed"
  );
}

export function setMode(mode) {
  return request(
    "/mode",
    {
      method: "POST",
      body: JSON.stringify({ mode })
    },
    "Mode update failed"
  );
}

export function triggerEmergencyOverride(contactId, reason) {
  return request(
    "/emergency/override",
    {
      method: "POST",
      body: JSON.stringify({ contactId, reason })
    },
    "Emergency override failed"
  );
}

export function fetchInsights() {
  return request("/insights", {}, "Insights fetch failed");
}

export function fetchUpdateStatus() {
  return request("/updates/status", {}, "Update status failed");
}

export function fetchSettings() {
  return request("/settings", {}, "Settings fetch failed");
}

export function saveSettings(patch) {
  return request(
    "/settings",
    {
      method: "PATCH",
      body: JSON.stringify(patch)
    },
    "Settings update failed"
  );
}

export function fetchProfile() {
  return request("/profile", {}, "Profile fetch failed");
}

export function saveProfile(patch) {
  return request(
    "/profile",
    {
      method: "PATCH",
      body: JSON.stringify(patch)
    },
    "Profile update failed"
  );
}

export function fetchReports(period = "weekly") {
  return request(`/reports?period=${encodeURIComponent(period)}`, {}, "Report fetch failed");
}

export function fetchAuditLogs() {
  return request("/audit-logs", {}, "Audit log fetch failed");
}

export function fetchWeather(latitude, longitude) {
  const params = latitude != null && longitude != null
    ? `?lat=${encodeURIComponent(latitude)}&lon=${encodeURIComponent(longitude)}`
    : "";
  return request(`/weather${params}`, {}, "Weather fetch failed");
}

export function translateText(payload) {
  return request(
    "/translate",
    {
      method: "POST",
      body: JSON.stringify(payload)
    },
    "Translation failed"
  );
}

export function fetchSteps() {
  return request("/steps", {}, "Steps fetch failed");
}

export function logSteps(payload) {
  return request(
    "/steps",
    {
      method: "POST",
      body: JSON.stringify(payload)
    },
    "Step logging failed"
  );
}

export function logSmartSteps(payload) {
  return request(
    "/steps/smart",
    {
      method: "POST",
      body: JSON.stringify(payload)
    },
    "Smart step logging failed"
  );
}

export function authorizeIntegration(platform, permissions) {
  return request(
    `/integrations/${platform}/authorize`,
    {
      method: "POST",
      body: JSON.stringify({ permissions })
    },
    "Integration authorization failed"
  );
}

export function chatWithAssistant(message) {
  return request(
    "/assistant/chat",
    {
      method: "POST",
      body: JSON.stringify({ message })
    },
    "Assistant request failed"
  );
}


