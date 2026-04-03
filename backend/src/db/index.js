import "dotenv/config";
import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { Pool } from "pg";

const dbEvents = new EventEmitter();
const now = () => new Date().toISOString();
const todayKey = (date = new Date()) => date.toISOString().slice(0, 10);
const FALLBACK_FILE = "chief.db.json";
const MAX_NOTIFICATIONS = 32;
const MAX_AUDIT_LOGS = 120;
const MAX_REPORT_SNAPSHOTS = 24;
const CLOUD_BUCKET = process.env.SUPABASE_WORKSPACE_BUCKET || "zyroai-workspaces";
const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY || "";
const POSTGRES_READY = Boolean(process.env.DATABASE_URL);
const STORAGE_READY = Boolean(SUPABASE_URL && SUPABASE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL ? { rejectUnauthorized: false } : false
});

let initialized = false;
let storageMode = "local-fallback";
let cloudBucketEnsured = false;
let fallbackMigratedToCloud = false;

const defaultProfile = () => ({
  name: "ZyroAi User",
  title: "Personal Command Center",
  email: "",
  avatar_url: "",
  avatar_color: "#f3cc78",
  language: "en",
  locale: "en-IN",
  city: "",
  timezone: process.env.DEFAULT_TIMEZONE || "Asia/Calcutta",
  daily_step_goal: 8000
});

const defaultSettings = () => ({
  appearance: {
    theme: "black-gold",
    density: "comfortable",
    reducedMotion: false
  },
  data: {
    storageMode: "cloud-managed",
    realtimeSync: true,
    analyticsOptIn: false,
    offlineReady: true,
    autoSyncWhenOnline: true
  },
  assistant: {
    persona: "ZyroAi Chief",
    voiceStyle: "calm",
    autoDecisionSupport: true,
    weeklyReports: true,
    monthlyReports: true,
    yearlyReports: true
  },
  automation: {
    dndMode: false,
    callAutoReply: true,
    smsAutoReply: true,
    wellbeingGuard: true,
    emergencyOverrideEnabled: true,
    autoStepTracking: false
  },
  permissions: {
    location: false,
    activity: false,
    notifications: false,
    microphone: false
  },
  integrations: {
    whatsapp: { connected: false, mode: "official-api-required", status: "not_authorized", permissions: [], last_synced_at: null },
    instagram: { connected: false, mode: "official-api-required", status: "not_authorized", permissions: [], last_synced_at: null },
    facebook: { connected: false, mode: "official-api-required", status: "not_authorized", permissions: [], last_synced_at: null },
    messenger: { connected: false, mode: "official-api-required", status: "not_authorized", permissions: [], last_synced_at: null },
    x: { connected: false, mode: "official-api-required", status: "not_authorized", permissions: [], last_synced_at: null }
  }
});

const makeNotification = (title, detail, severity = "info") => ({
  id: randomUUID(),
  title,
  detail,
  severity,
  status: "open",
  created_at: now()
});

const makeAuditLog = (action, detail, status = "success") => ({
  id: randomUUID(),
  action,
  detail,
  status,
  created_at: now()
});

const readFallbackStore = () => {
  if (!existsSync(FALLBACK_FILE)) {
    return {};
  }
  return JSON.parse(readFileSync(FALLBACK_FILE, "utf8"));
};

const writeFallbackStore = (store) => {
  writeFileSync(FALLBACK_FILE, JSON.stringify(store, null, 2), "utf8");
};

const cloudObjectPath = (deviceId) => `workspaces/${encodeURIComponent(deviceId)}.json`;

const supabaseHeaders = (extra = {}) => ({
  apikey: SUPABASE_SECRET_KEY,
  Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
  "User-Agent": "zyroai-backend/1.1.1",
  ...extra
});

const fetchJson = async (url, options = {}) => {
  const response = await fetch(url, options);
  const text = await response.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }
  return { response, data };
};

const ensureCloudBucket = async () => {
  if (!STORAGE_READY || cloudBucketEnsured) return;
  const list = await fetchJson(`${SUPABASE_URL}/storage/v1/bucket`, {
    headers: supabaseHeaders()
  });

  if (!list.response.ok) {
    throw new Error(typeof list.data === "string" ? list.data : list.data?.message || "Unable to list Supabase buckets");
  }

  const exists = Array.isArray(list.data) && list.data.some((bucket) => bucket?.name === CLOUD_BUCKET || bucket?.id === CLOUD_BUCKET);
  if (!exists) {
    const created = await fetchJson(`${SUPABASE_URL}/storage/v1/bucket`, {
      method: "POST",
      headers: supabaseHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({ id: CLOUD_BUCKET, name: CLOUD_BUCKET, public: false })
    });

    if (!created.response.ok) {
      throw new Error(typeof created.data === "string" ? created.data : created.data?.message || "Unable to create Supabase bucket");
    }
  }

  cloudBucketEnsured = true;
};

const loadCloudWorkspaceRow = async (deviceId) => {
  await ensureCloudBucket();
  const path = cloudObjectPath(deviceId);
  const { response, data } = await fetchJson(`${SUPABASE_URL}/storage/v1/object/${CLOUD_BUCKET}/${path}`, {
    headers: supabaseHeaders()
  });

  const missingObject = response.status === 404 || data?.message === "Object not found" || data === "Object not found";
  if (missingObject) {
    return null;
  }

  if (!response.ok) {
    throw new Error(typeof data === "string" ? data : data?.message || `Supabase cloud load failed with ${response.status}`);
  }

  return normalizeWorkspace(data);
};

const saveCloudWorkspaceRow = async (deviceId, workspace) => {
  await ensureCloudBucket();
  const normalized = normalizeWorkspace(workspace);
  const path = cloudObjectPath(deviceId);
  const { response, data } = await fetchJson(`${SUPABASE_URL}/storage/v1/object/${CLOUD_BUCKET}/${path}`, {
    method: "POST",
    headers: supabaseHeaders({
      "Content-Type": "application/json",
      "x-upsert": "true"
    }),
    body: JSON.stringify(normalized)
  });

  if (!response.ok) {
    throw new Error(typeof data === "string" ? data : data?.message || `Supabase cloud save failed with ${response.status}`);
  }
};

const maybeMigrateFallbackToCloud = async () => {
  if (!STORAGE_READY || fallbackMigratedToCloud || !existsSync(FALLBACK_FILE)) return;
  const fallbackStore = readFallbackStore();
  for (const [deviceId, workspace] of Object.entries(fallbackStore)) {
    const existing = await loadCloudWorkspaceRow(deviceId);
    if (!existing) {
      await saveCloudWorkspaceRow(deviceId, workspace);
    }
  }
  fallbackMigratedToCloud = true;
};

const createEmptyWorkspace = () => ({
  profile: defaultProfile(),
  settings: defaultSettings(),
  tasks: [],
  memories: [],
  call_logs: [],
  habits: [],
  meetings: [],
  contacts: [],
  notifications: [],
  decisions: [],
  mode_events: [{
    id: randomUUID(),
    mode: "Executive",
    deep_work_until: null,
    created_at: now()
  }],
  assistant_messages: [],
  step_entries: [],
  weather_cache: null,
  audit_logs: [makeAuditLog("workspace.created", "Workspace initialized for this device.")],
  report_snapshots: []
});

const normalizeWorkspace = (workspace = {}) => ({
  profile: {
    ...defaultProfile(),
    ...(workspace.profile || {})
  },
  settings: {
    appearance: {
      ...defaultSettings().appearance,
      ...(workspace.settings?.appearance || {})
    },
    data: {
      ...defaultSettings().data,
      ...(workspace.settings?.data || {})
    },
    assistant: {
      ...defaultSettings().assistant,
      ...(workspace.settings?.assistant || {})
    },
    automation: {
      ...defaultSettings().automation,
      ...(workspace.settings?.automation || {})
    },
    permissions: {
      ...defaultSettings().permissions,
      ...(workspace.settings?.permissions || {})
    },
    integrations: {
      ...defaultSettings().integrations,
      ...(workspace.settings?.integrations || {})
    }
  },
  tasks: workspace.tasks || [],
  memories: workspace.memories || [],
  call_logs: workspace.call_logs || [],
  habits: workspace.habits || [],
  meetings: workspace.meetings || [],
  contacts: workspace.contacts || [],
  notifications: workspace.notifications || [],
  decisions: workspace.decisions || [],
  mode_events: workspace.mode_events || [],
  assistant_messages: workspace.assistant_messages || [],
  step_entries: workspace.step_entries || [],
  weather_cache: workspace.weather_cache || null,
  audit_logs: workspace.audit_logs || [],
  report_snapshots: workspace.report_snapshots || []
});

const insertNotification = (workspace, title, detail, severity = "info") => {
  workspace.notifications.unshift(makeNotification(title, detail, severity));
  workspace.notifications = workspace.notifications.slice(0, MAX_NOTIFICATIONS);
};

const insertAuditLog = (workspace, action, detail, status = "success") => {
  workspace.audit_logs.unshift(makeAuditLog(action, detail, status));
  workspace.audit_logs = workspace.audit_logs.slice(0, MAX_AUDIT_LOGS);
};

const emitChange = (deviceId, type) => {
  dbEvents.emit("change", { deviceId, type, at: now() });
};

const ensureInit = async () => {
  if (initialized) return;
  if (POSTGRES_READY) {
    try {
      await pool.query(`
        create table if not exists chief_workspaces (
          device_id text primary key,
          workspace jsonb not null,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        );
      `);
      storageMode = "supabase-postgres";
      initialized = true;
      return;
    } catch (error) {
      console.warn(`Chief Postgres storage unavailable, trying cloud storage: ${error.code || error.message}`);
    }
  }

  if (STORAGE_READY) {
    try {
      await ensureCloudBucket();
      await maybeMigrateFallbackToCloud();
      storageMode = "supabase-cloud";
      initialized = true;
      return;
    } catch (error) {
      console.warn(`Chief cloud storage unavailable, using local fallback: ${error.code || error.message}`);
    }
  }

  storageMode = "local-fallback";
  initialized = true;
};

const loadWorkspaceRow = async (deviceId) => {
  await ensureInit();
  if (storageMode === "local-fallback") {
    const store = readFallbackStore();
    return store[deviceId] ? normalizeWorkspace(store[deviceId]) : null;
  }
  if (storageMode === "supabase-cloud") {
    return loadCloudWorkspaceRow(deviceId);
  }
  const { rows } = await pool.query("select workspace from chief_workspaces where device_id = $1", [deviceId]);
  return rows[0]?.workspace ? normalizeWorkspace(rows[0].workspace) : null;
};

const saveWorkspaceRow = async (deviceId, workspace) => {
  await ensureInit();
  const normalized = normalizeWorkspace(workspace);
  if (storageMode === "local-fallback") {
    const store = readFallbackStore();
    store[deviceId] = normalized;
    writeFallbackStore(store);
    return;
  }
  if (storageMode === "supabase-cloud") {
    await saveCloudWorkspaceRow(deviceId, normalized);
    return;
  }
  await pool.query(
    `
      insert into chief_workspaces (device_id, workspace, created_at, updated_at)
      values ($1, $2::jsonb, now(), now())
      on conflict (device_id)
      do update set workspace = excluded.workspace, updated_at = now()
    `,
    [deviceId, JSON.stringify(normalized)]
  );
};

const integrationDisplayNames = {
  whatsapp: "WhatsApp",
  instagram: "Instagram",
  facebook: "Facebook",
  messenger: "Messenger",
  x: "X"
};

const actionLabels = {
  user_seeded: "Device workspace was initialized.",
  mode_changed: "Mode state changed.",
  task_updated: "Task record was updated.",
  task_status_changed: "Task status changed.",
  memory_added: "Memory entry added.",
  call_logged: "Communication was logged.",
  habit_checked_in: "Habit was checked in.",
  habit_added: "Habit added.",
  meeting_added: "Meeting added.",
  contact_added: "Contact added.",
  emergency_override: "Emergency override triggered.",
  decision_recorded: "Decision saved.",
  settings_updated: "Settings were updated.",
  assistant_replied: "Assistant conversation updated.",
  profile_updated: "Profile updated.",
  steps_logged: "Daily steps updated.",
  weather_cached: "Weather cache refreshed.",
  report_saved: "AI report snapshot saved."
};

const mutateWorkspace = async (deviceId, type, mutator, detail) => {
  const workspace = (await loadWorkspace(deviceId)) || createEmptyWorkspace();
  const result = await mutator(workspace);
  insertAuditLog(workspace, type, detail || actionLabels[type] || "Workspace action completed.");
  await saveWorkspaceRow(deviceId, workspace);
  emitChange(deviceId, type);
  return result;
};

export const ensureUser = async (deviceId) => {
  const workspace = await loadWorkspaceRow(deviceId);
  if (workspace) return workspace;
  const fresh = createEmptyWorkspace();
  await saveWorkspaceRow(deviceId, fresh);
  emitChange(deviceId, "user_seeded");
  return fresh;
};

export const subscribeToDeviceChanges = (deviceId, listener) => {
  const wrapped = (event) => {
    if (event.deviceId === deviceId) listener(event);
  };
  dbEvents.on("change", wrapped);
  return () => dbEvents.off("change", wrapped);
};

const loadWorkspace = async (deviceId) => normalizeWorkspace(await ensureUser(deviceId));

const latestModeOrDefault = (workspace) => [...workspace.mode_events].sort((a, b) => b.created_at.localeCompare(a.created_at))[0] || {
  mode: "Executive",
  deep_work_until: null,
  created_at: now()
};

const getTodayStepEntry = (workspace, dateKey = todayKey()) =>
  workspace.step_entries.find((entry) => entry.date === dateKey) || null;

export const getModeState = async (deviceId) => latestModeOrDefault(await loadWorkspace(deviceId));

export const setModeState = async (deviceId, mode) =>
  mutateWorkspace(deviceId, "mode_changed", async (workspace) => {
    const entry = {
      id: randomUUID(),
      mode,
      deep_work_until: mode === "Deep Work" ? new Date(Date.now() + 7_200_000).toISOString() : null,
      created_at: now()
    };
    workspace.mode_events.push(entry);
    insertNotification(workspace, "Mode updated", `Chief switched to ${mode} mode.`, "info");
    return entry;
  }, `Mode switched to ${mode}.`);

export const listTasks = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.tasks].sort((a, b) => b.priority_score - a.priority_score || String(a.due_at || "").localeCompare(String(b.due_at || "")));
};

export const upsertTask = async (deviceId, task) =>
  mutateWorkspace(deviceId, "task_updated", async (workspace) => {
    const id = task.id || randomUUID();
    const existingIndex = workspace.tasks.findIndex((item) => item.id === id);
    const record = {
      id,
      title: task.title,
      due_at: task.dueAt || null,
      priority_score: task.priorityScore,
      status: task.status || "todo",
      energy_band: task.energyBand || "medium",
      category: task.category || "Execution",
      completed_at: task.status === "done" ? now() : null,
      created_at: existingIndex >= 0 ? workspace.tasks[existingIndex].created_at : now()
    };
    if (existingIndex >= 0) {
      workspace.tasks[existingIndex] = { ...workspace.tasks[existingIndex], ...record };
    } else {
      workspace.tasks.push(record);
    }
    insertNotification(workspace, "Task updated", `${record.title} is now in ${record.status.replace("_", " ")}.`, "info");
    return id;
  }, `Task ${task.title} saved.`);

export const updateTaskStatus = async (deviceId, taskId, status) =>
  mutateWorkspace(deviceId, "task_status_changed", async (workspace) => {
    const task = workspace.tasks.find((item) => item.id === taskId);
    if (!task) return null;
    task.status = status;
    task.completed_at = status === "done" ? now() : null;
    insertNotification(workspace, "Task status changed", `${task.title} moved to ${status.replace("_", " ")}.`, "info");
    return task;
  }, `Task ${taskId} moved to ${status}.`);

export const addMemory = async (deviceId, encryptedNote, hint) =>
  mutateWorkspace(deviceId, "memory_added", async (workspace) => {
    const id = randomUUID();
    workspace.memories.unshift({ id, encrypted_note: encryptedNote, hint, created_at: now() });
    insertNotification(workspace, "Memory saved", `Stored memory: ${hint}.`, "info");
    return id;
  }, `Memory stored for ${hint}.`);

export const listMemories = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.memories]
    .sort((a, b) => b.created_at.localeCompare(a.created_at))
    .map((memory) => ({ id: memory.id, hint: memory.hint, created_at: memory.created_at }));
};

export const addCallLog = async (deviceId, payload) =>
  mutateWorkspace(deviceId, "call_logged", async (workspace) => {
    const id = randomUUID();
    workspace.call_logs.unshift({
      id,
      caller: payload.caller,
      transcript: payload.transcript,
      sentiment: payload.sentiment,
      urgency: payload.urgency,
      agent_reply: payload.agentReply || "",
      handled_by_dnd: Boolean(payload.handledByDnd),
      created_at: now()
    });
    insertNotification(
      workspace,
      "Communication captured",
      payload.handledByDnd
        ? `${payload.caller} was handled by DND auto-reply.`
        : `${payload.caller} left a ${payload.sentiment} message.`,
      payload.urgency > 75 ? "critical" : "info"
    );
    return id;
  }, `Call log saved for ${payload.caller}.`);

export const listCallLogs = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.call_logs].sort((a, b) => b.created_at.localeCompare(a.created_at));
};

export const listHabits = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.habits].sort((a, b) => a.name.localeCompare(b.name));
};

export const checkInHabit = async (deviceId, habitId) =>
  mutateWorkspace(deviceId, "habit_checked_in", async (workspace) => {
    const habit = workspace.habits.find((item) => item.id === habitId);
    if (!habit) return null;
    const currentDate = todayKey();
    const todayCount = habit.last_check_in_date === currentDate ? habit.completed_today : 0;
    habit.completed_today = Math.min(habit.target_per_day, todayCount + 1);
    habit.last_check_in_date = currentDate;
    habit.streak += 1;
    insertNotification(workspace, "Habit completed", `${habit.name} checked off.`, "success");
    return habit;
  }, `Habit ${habitId} checked in.`);

export const addHabit = async (deviceId, name) =>
  mutateWorkspace(deviceId, "habit_added", async (workspace) => {
    const habit = {
      id: randomUUID(),
      name,
      streak: 0,
      target_per_day: 1,
      completed_today: 0,
      last_check_in_date: null,
      created_at: now()
    };
    workspace.habits.push(habit);
    insertNotification(workspace, "Habit added", `${name} was added to your rituals.`, "info");
    return habit;
  }, `Habit ${name} added.`);

export const listMeetings = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.meetings].sort((a, b) => a.start_at.localeCompare(b.start_at));
};

export const addMeeting = async (deviceId, meeting) =>
  mutateWorkspace(deviceId, "meeting_added", async (workspace) => {
    const record = {
      id: randomUUID(),
      title: meeting.title,
      owner: meeting.owner,
      start_at: meeting.startAt,
      duration_minutes: meeting.durationMinutes,
      notes: meeting.notes,
      status: "scheduled",
      created_at: now()
    };
    workspace.meetings.push(record);
    insertNotification(workspace, "Meeting added", `${record.title} was scheduled.`, "info");
    return record;
  }, `Meeting ${meeting.title} scheduled.`);

export const listContacts = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.contacts].sort((a, b) => (a.tier === b.tier ? a.name.localeCompare(b.name) : a.tier === "vip" ? -1 : 1));
};

export const addContact = async (deviceId, contact) =>
  mutateWorkspace(deviceId, "contact_added", async (workspace) => {
    const record = {
      id: randomUUID(),
      name: contact.name,
      relationship: contact.relationship,
      tier: contact.tier || "standard",
      phone: contact.phone || "",
      created_at: now()
    };
    workspace.contacts.push(record);
    insertNotification(workspace, "Contact added", `${record.name} was added to your directory.`, "info");
    return record;
  }, `Contact ${contact.name} saved.`);

export const triggerEmergencyOverride = async (deviceId, payload) =>
  mutateWorkspace(deviceId, "emergency_override", async (workspace) => {
    const contact = workspace.contacts.find((item) => item.id === payload.contactId);
    if (!contact) return null;
    const notification = makeNotification(
      "Emergency override",
      `${contact.name} was allowed to break through busy mode for: ${payload.reason}.`,
      "critical"
    );
    workspace.notifications.unshift(notification);
    return notification;
  }, `Emergency override used for ${payload.contactId}.`);

export const listNotifications = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.notifications].sort((a, b) => b.created_at.localeCompare(a.created_at));
};

export const addDecisionRecord = async (deviceId, decision) =>
  mutateWorkspace(deviceId, "decision_recorded", async (workspace) => {
    const record = {
      id: randomUUID(),
      title: decision.title,
      recommendation: decision.recommendation,
      confidence: decision.confidence,
      created_at: now()
    };
    workspace.decisions.unshift(record);
    insertNotification(workspace, "Decision stored", `${decision.title} recommendation saved.`, "info");
    return record;
  }, `Decision saved for ${decision.title}.`);

export const listDecisions = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.decisions].sort((a, b) => b.created_at.localeCompare(a.created_at));
};

export const getSettings = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return workspace.settings;
};

export const updateSettings = async (deviceId, patch) =>
  mutateWorkspace(deviceId, "settings_updated", async (workspace) => {
    const defaults = defaultSettings();
    const mergedIntegrations = { ...defaults.integrations, ...workspace.settings.integrations };
    for (const [platform, config] of Object.entries(patch.integrations || {})) {
      mergedIntegrations[platform] = {
        ...(defaults.integrations[platform] || {}),
        ...(workspace.settings.integrations?.[platform] || {}),
        ...config
      };
    }
    workspace.settings = {
      appearance: { ...defaults.appearance, ...workspace.settings.appearance, ...(patch.appearance || {}) },
      data: { ...defaults.data, ...workspace.settings.data, ...(patch.data || {}) },
      assistant: { ...defaults.assistant, ...workspace.settings.assistant, ...(patch.assistant || {}) },
      automation: { ...defaults.automation, ...workspace.settings.automation, ...(patch.automation || {}) },
      permissions: { ...defaults.permissions, ...workspace.settings.permissions, ...(patch.permissions || {}) },
      integrations: mergedIntegrations
    };
    insertNotification(workspace, "Settings updated", "Chief preferences were updated.", "info");
    return workspace.settings;
  }, "Settings updated.");

export const getProfile = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return workspace.profile;
};

export const updateProfile = async (deviceId, patch) =>
  mutateWorkspace(deviceId, "profile_updated", async (workspace) => {
    workspace.profile = { ...defaultProfile(), ...workspace.profile, ...patch };
    insertNotification(workspace, "Profile updated", "Identity and personalization settings saved.", "info");
    return workspace.profile;
  }, "Profile saved.");

export const getAssistantMessages = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.assistant_messages].sort((a, b) => a.created_at.localeCompare(b.created_at));
};

export const addAssistantMessagePair = async (deviceId, question, answer) =>
  mutateWorkspace(deviceId, "assistant_replied", async (workspace) => {
    const userMessage = { id: randomUUID(), role: "user", content: question, created_at: now() };
    const assistantMessage = { id: randomUUID(), role: "assistant", content: answer, created_at: now() };
    workspace.assistant_messages.push(userMessage, assistantMessage);
    return assistantMessage;
  }, "Assistant produced a response.");

export const listAuditLogs = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.audit_logs].sort((a, b) => b.created_at.localeCompare(a.created_at));
};

export const getStepSummary = async (deviceId, dateKey = todayKey()) => {
  const workspace = await loadWorkspace(deviceId);
  const entry = getTodayStepEntry(workspace, dateKey);
  const goal = workspace.profile.daily_step_goal || 8000;
  const count = entry?.count || 0;
  return {
    date: dateKey,
    count,
    goal,
    progress: Math.min(100, Math.round((count / Math.max(goal, 1)) * 100)),
    source: entry?.source || "manual",
    updated_at: entry?.updated_at || null
  };
};

export const logDailySteps = async (deviceId, payload) =>
  mutateWorkspace(deviceId, "steps_logged", async (workspace) => {
    const date = payload.date || todayKey();
    const goal = workspace.profile.daily_step_goal || 8000;
    const existing = workspace.step_entries.find((entry) => entry.date === date);
    const nextCount = payload.mode === "set"
      ? Math.max(0, payload.count)
      : Math.max(0, (existing?.count || 0) + payload.count);

    if (existing) {
      existing.count = nextCount;
      existing.goal = goal;
      existing.source = payload.source || existing.source || "manual";
      existing.updated_at = now();
    } else {
      workspace.step_entries.unshift({
        id: randomUUID(),
        date,
        count: nextCount,
        goal,
        source: payload.source || "manual",
        updated_at: now()
      });
    }

    insertNotification(workspace, "Footsteps updated", `${nextCount} steps recorded for ${date}.`, nextCount >= goal ? "success" : "info");
    return getTodayStepEntry(workspace, date);
  }, `Steps recorded for ${payload.date || todayKey()}.`);

export const logSmartSteps = async (deviceId, payload) =>
  mutateWorkspace(deviceId, "steps_logged", async (workspace) => {
    const date = payload.date || todayKey();
    const goal = workspace.profile.daily_step_goal || 8000;
    const existing = workspace.step_entries.find((entry) => entry.date === date);
    const currentCount = existing?.count || 0;
    const distanceMeters = Math.max(0, Number(payload.distance_meters || 0));
    const durationSeconds = Math.max(1, Number(payload.duration_seconds || 1));
    const speedMps = payload.speed_mps != null
      ? Math.max(0, Number(payload.speed_mps))
      : distanceMeters / durationSeconds;
    const isWalkingSpeed = speedMps >= 0.35 && speedMps <= 2.6;
    const inferredTravel = payload.activity_hint === "vehicle" || speedMps > 2.6;
    const shouldCount = Boolean(workspace.settings.permissions.location && workspace.settings.permissions.activity && isWalkingSpeed && !inferredTravel);
    const estimatedSteps = shouldCount ? Math.max(0, Math.round(distanceMeters / 0.78)) : 0;
    const nextCount = currentCount + estimatedSteps;
    const updatedAt = now();

    const nextEntry = {
      id: existing?.id || randomUUID(),
      date,
      count: nextCount,
      goal,
      source: shouldCount ? "geo-auto" : "vehicle-filtered",
      updated_at: updatedAt,
      auto: {
        distance_meters: distanceMeters,
        duration_seconds: durationSeconds,
        speed_mps: Number(speedMps.toFixed(2)),
        activity_hint: inferredTravel ? "vehicle" : "walking",
        last_steps_added: estimatedSteps,
        last_filtered: !shouldCount
      }
    };

    if (existing) {
      Object.assign(existing, nextEntry);
    } else {
      workspace.step_entries.unshift(nextEntry);
    }

    insertNotification(
      workspace,
      shouldCount ? "Auto steps captured" : "Vehicle movement ignored",
      shouldCount
        ? `${estimatedSteps} walking steps were estimated from live movement.`
        : "Movement was ignored because ZyroAi detected vehicle-speed travel.",
      shouldCount && nextCount >= goal ? "success" : "info"
    );

    return {
      ...getTodayStepEntry(workspace, date),
      added_steps: estimatedSteps,
      counted: shouldCount
    };
  }, "Smart movement update processed.");

export const authorizeIntegration = async (deviceId, platform, permissions) =>
  mutateWorkspace(deviceId, "settings_updated", async (workspace) => {
    const defaults = defaultSettings();
    const current = {
      ...(defaults.integrations[platform] || {}),
      ...(workspace.settings.integrations?.[platform] || {})
    };
    workspace.settings.integrations[platform] = {
      ...current,
      connected: true,
      status: "authorized",
      mode: "consent-granted",
      permissions,
      last_synced_at: now()
    };
    insertNotification(
      workspace,
      `${integrationDisplayNames[platform] || platform} linked`,
      `Authorization was granted for ${permissions.join(", ")} access.`,
      "success"
    );
    return workspace.settings.integrations[platform];
  }, `${integrationDisplayNames[platform] || platform} authorized.`);

export const getWeatherCache = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return workspace.weather_cache;
};

export const setWeatherCache = async (deviceId, payload) =>
  mutateWorkspace(deviceId, "weather_cached", async (workspace) => {
    workspace.weather_cache = {
      ...payload,
      cached_at: now()
    };
    return workspace.weather_cache;
  }, "Weather cache refreshed.");

export const saveReportSnapshot = async (deviceId, snapshot) =>
  mutateWorkspace(deviceId, "report_saved", async (workspace) => {
    workspace.report_snapshots.unshift({ id: randomUUID(), ...snapshot, created_at: now() });
    workspace.report_snapshots = workspace.report_snapshots.slice(0, MAX_REPORT_SNAPSHOTS);
    return workspace.report_snapshots[0];
  }, `${snapshot.period} report generated.`);

export const listReportSnapshots = async (deviceId) => {
  const workspace = await loadWorkspace(deviceId);
  return [...workspace.report_snapshots].sort((a, b) => b.created_at.localeCompare(a.created_at));
};

export const getWorkspaceSnapshot = async (deviceId) => loadWorkspace(deviceId);
export const getStorageMode = () => storageMode;
