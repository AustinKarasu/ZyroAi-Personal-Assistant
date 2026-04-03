import { startTransition, useEffect, useMemo, useState } from "react";
import DashboardPage from "./pages/DashboardPage";
import PlannerPage from "./pages/PlannerPage";
import CommunicationPage from "./pages/CommunicationPage";
import AssistantPage from "./pages/AssistantPage";
import SettingsPage from "./pages/SettingsPage";
import IntelligencePage from "./pages/IntelligencePage";
import {
  addCallLog,
  addContact,
  addHabit,
  addMeeting,
  addMemory,
  addTask,
  authorizeIntegration,
  cacheWorkspace,
  chatWithAssistant,
  clearLocalState,
  checkInHabit,
  chiefDeviceId,
  decide,
  fetchReports,
  fetchWeather,
  fetchWorkspace,
  generateAutoReply,
  handleIncomingCall,
  logSmartSteps,
  logSteps,
  readCachedWorkspace,
  saveProfile,
  saveSettings,
  setMode,
  subscribeToWorkspace,
  translateText as translateApi,
  triggerEmergencyOverride,
  updateTaskStatus,
  appVersion
} from "./api/client";
import { getDirection, t } from "./i18n";
import "./styles/app.css";

const tabs = ["home", "planner", "calls", "intelligence", "assistant", "settings"];
const offlineErrorPattern = /failed to fetch|networkerror|network request failed|load failed/i;
const updateDismissKey = (version) => `zyroai_update_dismissed_${version}`;
const installedVersionKey = "zyroai_installed_version";

const isOfflineError = (error) => error instanceof TypeError || offlineErrorPattern.test(String(error?.message || error));
const createId = () => `offline-${crypto.randomUUID()}`;
const now = () => new Date().toISOString();

const autoReplyTemplates = {
  meeting: (sender, until) => `Hi ${sender}, I am in a meeting until ${until}. I will review this right after.`,
  deep_work: (sender, until) => `Hi ${sender}, I am in a deep work block until ${until}. I will get back with a clear response.`,
  driving: (sender, until) => `Hi ${sender}, I am currently driving. I will reply safely after ${until}.`,
  busy: (sender, until) => `Hi ${sender}, I am tied up until ${until}. I will check this as soon as possible.`
};

const buildOfflineAssistantReply = (workspace, message) => {
  const lower = message.toLowerCase();
  if (lower.includes("report")) {
    return workspace?.reports?.latest?.weekly?.highlights?.join(" ") || "Offline report cache is ready once live data syncs again.";
  }
  if (lower.includes("weather")) {
    return workspace?.weather ? `Cached weather: ${workspace.weather.summary} at ${workspace.weather.temperatureC} C.` : "Weather is not cached yet. Connect once to refresh local weather.";
  }
  if (lower.includes("step") || lower.includes("walk")) {
    return `Today you have ${(workspace?.steps?.count || 0).toLocaleString()} steps recorded locally.`;
  }
  if (lower.includes("dnd")) {
    return workspace?.settings?.automation?.dndMode ? "DND is active in offline mode too." : "DND is currently off.";
  }
  return "ZyroAi is in offline mode. Your changes are being kept on this device until live sync returns.";
};

const mergeWorkspace = (current, updater) => {
  const next = updater(current);
  cacheWorkspace(next);
  return next;
};

export default function App() {
  const [activeTab, setActiveTab] = useState("home");
  const [workspace, setWorkspace] = useState(readCachedWorkspace());
  const [busyKey, setBusyKey] = useState("");
  const [connectionState, setConnectionState] = useState("Connecting");
  const [loadError, setLoadError] = useState("");
  const [banner, setBanner] = useState("");
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [showUpdateModal, setShowUpdateModal] = useState(false);

  async function loadWorkspace() {
    try {
      const next = await fetchWorkspace();
      setWorkspace(next);
      setLoadError("");
      setConnectionState(next.offline ? t(next.profile?.language || "en", "offlineActive") : t(next.profile?.language || "en", "realtimeLinked"));
    } catch (error) {
      const cached = readCachedWorkspace();
      if (cached) {
        setWorkspace(cached);
        setConnectionState("Offline device mode");
        setBanner("Using offline device cache until live sync returns.");
        return;
      }
      setLoadError(error.message || "Failed to load ZyroAi workspace.");
      setConnectionState("Retry needed");
    }
  }

  useEffect(() => {
    let mounted = true;
    loadWorkspace();
    const unsubscribe = subscribeToWorkspace((next) => {
      if (!mounted) return;
      setConnectionState(t(next.profile?.language || "en", "realtimeLinked"));
      setLoadError("");
      startTransition(() => {
        setWorkspace(next);
      });
    });

    return () => {
      mounted = false;
      unsubscribe();
    };
  }, []);

  useEffect(() => {
    const appearance = workspace?.settings?.appearance;
    const language = workspace?.profile?.language || "en";
    if (appearance) {
      document.documentElement.dataset.theme = appearance.theme || "black-gold";
      document.documentElement.dataset.density = appearance.density || "comfortable";
      document.documentElement.classList.toggle("reduced-motion", Boolean(appearance.reducedMotion));
    }
    document.documentElement.dir = getDirection(language);
    document.documentElement.lang = language;
  }, [workspace?.settings?.appearance, workspace?.profile?.language]);


  useEffect(() => {
    const currentVersion = appVersion || workspace?.updateCenter?.currentVersion;
    if (!currentVersion) return;
    const installedVersion = localStorage.getItem(installedVersionKey);
    if (installedVersion && installedVersion !== currentVersion) {
      clearLocalState().finally(() => {
        localStorage.setItem(installedVersionKey, currentVersion);
        window.location.reload();
      });
      return;
    }
    localStorage.setItem(installedVersionKey, currentVersion);
  }, [workspace?.updateCenter?.currentVersion]);

  useEffect(() => {
    const latestVersion = workspace?.updateCenter?.latestVersion;
    const currentVersion = appVersion || workspace?.updateCenter?.currentVersion;
    if (!workspace?.updateCenter?.updateAvailable || !latestVersion || !currentVersion) return;
    if (latestVersion === currentVersion) {
      setShowUpdateModal(false);
      return;
    }
    if (!localStorage.getItem(updateDismissKey(latestVersion))) {
      setShowUpdateModal(true);
    }
  }, [workspace?.updateCenter?.latestVersion, workspace?.updateCenter?.updateAvailable, workspace?.updateCenter?.currentVersion]);

  const localizedTabs = useMemo(
    () => tabs.map((key) => ({ key, label: t(workspace?.profile?.language || "en", key) })),
    [workspace?.profile?.language]
  );

  async function runAction(key, task, offlineUpdater, fallbackResult) {
    setBusyKey(key);
    setBanner("");
    try {
      const result = await task();
      await loadWorkspace();
      return result;
    } catch (error) {
      if (isOfflineError(error) && workspace && offlineUpdater) {
        setWorkspace((current) => mergeWorkspace(current, offlineUpdater));
        setConnectionState("Offline device mode");
        setBanner("Saved locally. ZyroAi will keep working on this device offline.");
        return typeof fallbackResult === "function" ? fallbackResult(workspace) : fallbackResult;
      }
      setLoadError(error.message || "Action failed.");
      throw error;
    } finally {
      setBusyKey("");
    }
  }

  const actions = {
    createTask: (payload) => runAction(
      "create-task",
      () => addTask(payload),
      (current) => ({
        ...current,
        tasks: {
          ...current.tasks,
          all: [{
            id: createId(),
            title: payload.title,
            due_at: payload.dueAt || null,
            priority_score: 88,
            status: "todo",
            energy_band: payload.energyBand || "medium",
            category: payload.category || "Execution",
            created_at: now()
          }, ...current.tasks.all],
          grouped: {
            ...current.tasks.grouped,
            todo: [{
              id: createId(),
              title: payload.title,
              due_at: payload.dueAt || null,
              priority_score: 88,
              status: "todo",
              energy_band: payload.energyBand || "medium",
              category: payload.category || "Execution",
              created_at: now()
            }, ...current.tasks.grouped.todo]
          }
        },
        notifications: [{ id: createId(), title: "Task queued offline", detail: `${payload.title} was stored locally.`, severity: "info", created_at: now() }, ...current.notifications].slice(0, 8)
      })
    ),
    setTaskStatus: (taskId, status) => runAction(
      `task-${taskId}`,
      () => updateTaskStatus(taskId, status),
      (current) => {
        const all = current.tasks.all.map((task) => task.id === taskId ? { ...task, status } : task);
        return {
          ...current,
          tasks: {
            all,
            grouped: {
              todo: all.filter((task) => task.status === "todo"),
              inProgress: all.filter((task) => task.status === "in_progress"),
              done: all.filter((task) => task.status === "done")
            }
          }
        };
      }
    ),
    analyzeCall: (caller, transcript) => runAction(
      "call-analysis",
      () => addCallLog(caller, transcript),
      (current) => ({
        ...current,
        communications: {
          ...current.communications,
          calls: [{ id: createId(), caller, transcript, sentiment: "offline", urgency: 20, created_at: now(), handled_by_dnd: false }, ...current.communications.calls]
        }
      })
    ),
    makeReply: (sender, context, until) => runAction(
      "auto-reply",
      () => generateAutoReply(sender, context, until),
      null,
      { message: (autoReplyTemplates[context] || autoReplyTemplates.busy)(sender, until) }
    ),
    saveMemory: (hint, note) => runAction(
      "save-memory",
      () => addMemory(hint, note),
      (current) => ({
        ...current,
        memories: [{ id: createId(), hint, created_at: now() }, ...current.memories]
      })
    ),
    saveHabit: (name) => runAction(
      "save-habit",
      () => addHabit(name),
      (current) => ({
        ...current,
        habits: [...current.habits, { id: createId(), name, streak: 0, target_per_day: 1, completed_today: 0, created_at: now() }]
      })
    ),
    checkInHabit: (habitId) => runAction(
      `habit-${habitId}`,
      () => checkInHabit(habitId),
      (current) => ({
        ...current,
        habits: current.habits.map((habit) => habit.id === habitId ? { ...habit, completed_today: Math.min(habit.target_per_day, (habit.completed_today || 0) + 1), streak: (habit.streak || 0) + 1 } : habit)
      })
    ),
    saveMeeting: (payload) => runAction(
      "save-meeting",
      () => addMeeting(payload),
      (current) => ({
        ...current,
        agenda: [...current.agenda, { id: createId(), title: payload.title, owner: payload.owner, start_at: payload.startAt, duration_minutes: payload.durationMinutes, notes: payload.notes }]
      })
    ),
    saveContact: (payload) => runAction(
      "save-contact",
      () => addContact(payload),
      (current) => ({
        ...current,
        contacts: [...current.contacts, { id: createId(), ...payload, created_at: now() }]
      })
    ),
    setMode: (mode) => runAction(
      `mode-${mode}`,
      () => setMode(mode),
      (current) => ({
        ...current,
        overview: { ...current.overview, liveMode: mode }
      })
    ),
    runDecision: (payload) => runAction(
      "run-decision",
      () => decide(payload),
      null,
      { recommendation: `Offline recommendation: start with ${payload.options[0]?.name || "the simplest option"}.`, confidence: 62 }
    ),
    triggerEmergency: (contactId, reason) => runAction("emergency", () => triggerEmergencyOverride(contactId, reason)),
    handleIncomingCall: (caller, transcript) => runAction(
      "incoming-call",
      () => handleIncomingCall(caller, transcript),
      (current) => {
        const handledByDnd = Boolean(current.settings?.automation?.dndMode && current.settings?.automation?.callAutoReply);
        return {
          ...current,
          communications: {
            ...current.communications,
            calls: [{ id: createId(), caller, transcript, sentiment: "offline", urgency: 30, created_at: now(), handled_by_dnd: handledByDnd, agent_reply: handledByDnd ? "The person is currently busy, drop your message for the user." : "" }, ...current.communications.calls]
          }
        };
      },
      {
        handledByDnd: Boolean(workspace?.settings?.automation?.dndMode && workspace?.settings?.automation?.callAutoReply),
        agentReply: workspace?.settings?.automation?.dndMode ? "The person is currently busy, drop your message for the user." : "",
        summary: "Incoming call stored locally while offline."
      }
    ),
    chat: (message) => runAction(
      "assistant-chat",
      () => chatWithAssistant(message),
      (current) => ({
        ...current,
        assistant: {
          ...current.assistant,
          messages: [
            ...current.assistant.messages,
            { id: createId(), role: "user", content: message, created_at: now() },
            { id: createId(), role: "assistant", content: buildOfflineAssistantReply(current, message), created_at: now() }
          ]
        }
      }),
      { message: { id: createId(), role: "assistant", content: buildOfflineAssistantReply(workspace, message), created_at: now() } }
    ),
    saveSettings: (patch) => runAction(
      "save-settings",
      () => saveSettings(patch),
      (current) => ({
        ...current,
        settings: {
          ...current.settings,
          ...patch,
          appearance: { ...current.settings.appearance, ...(patch.appearance || {}) },
          assistant: { ...current.settings.assistant, ...(patch.assistant || {}) },
          automation: { ...current.settings.automation, ...(patch.automation || {}) },
          data: { ...current.settings.data, ...(patch.data || {}) },
          permissions: { ...(current.settings.permissions || {}), ...(patch.permissions || {}) },
          integrations: { ...(current.settings.integrations || {}), ...(patch.integrations || {}) }
        }
      })
    ),
    saveProfile: (patch) => runAction(
      "save-profile",
      () => saveProfile(patch),
      (current) => ({
        ...current,
        profile: { ...current.profile, ...patch }
      })
    ),
    refreshWeather: (latitude, longitude) => runAction(
      "weather-refresh",
      () => fetchWeather(latitude, longitude),
      null,
      { weather: workspace?.weather || null, source: workspace?.weather ? "cache" : "offline" }
    ),
    authorizeIntegration: (platform, permissions) => runAction(
      `integration-${platform}`,
      () => authorizeIntegration(platform, permissions)
    ),
    generateReport: (period) => runAction(
      `report-${period}`,
      () => fetchReports(period),
      null,
      { report: workspace?.reports?.latest?.[period] || null }
    ),
    translateText: (payload) => translateApi(payload),
    logSteps: (payload) => runAction(
      "log-steps",
      () => logSteps(payload),
      (current) => {
        const nextCount = payload.mode === "set" ? payload.count : (current.steps?.count || 0) + payload.count;
        return {
          ...current,
          steps: {
            ...current.steps,
            count: nextCount,
            progress: Math.min(100, Math.round((nextCount / Math.max(current.profile?.daily_step_goal || current.steps.goal || 8000, 1)) * 100))
          }
        };
      }
    ),
    logSmartSteps: (payload) => runAction(
      `smart-steps-${payload.date || "today"}`,
      () => logSmartSteps(payload)
    )
  };

  const pageProps = {
    workspace,
    busyKey,
    actions,
    language: workspace?.profile?.language || "en"
  };

  const pageMap = {
    home: <DashboardPage {...pageProps} />,
    planner: <PlannerPage {...pageProps} />,
    calls: <CommunicationPage {...pageProps} />,
    intelligence: <IntelligencePage {...pageProps} />,
    assistant: <AssistantPage {...pageProps} />,
    settings: <SettingsPage {...pageProps} />
  };

  const dismissUpdate = () => {
    if (workspace?.updateCenter?.latestVersion) {
      localStorage.setItem(updateDismissKey(workspace.updateCenter.latestVersion), "1");
    }
    setShowUpdateModal(false);
  };

  const handleUpdateNow = async () => {
    const latestVersion = workspace?.updateCenter?.latestVersion;
    const downloadUrl = workspace?.updateCenter?.downloadUrl;
    await clearLocalState();
    if (latestVersion) {
      localStorage.setItem(updateDismissKey(latestVersion), "1");
    }
    setShowUpdateModal(false);
    if (downloadUrl) {
      window.location.href = downloadUrl;
      return;
    }
    window.location.reload();
  };

  return (
    <div className="zyro-app">
      {drawerOpen ? <button type="button" className="drawer-scrim" aria-label="Close navigation" onClick={() => setDrawerOpen(false)} /> : null}
      <aside className={`side-drawer ${drawerOpen ? "open" : ""}`}>
        <div className="drawer-head">
          <img className="brand-logo" src="/zyroai-logo.jpg" alt="ZyroAi logo" />
          <div>
            <strong>ZyroAi</strong>
            <small>Executive command drawer</small>
          </div>
        </div>
        <div className="drawer-list">
          {localizedTabs.map((tab) => (
            <button
              key={tab.key}
              type="button"
              className={activeTab === tab.key ? "active" : ""}
              onClick={() => {
                setActiveTab(tab.key);
                setDrawerOpen(false);
              }}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </aside>

      {showUpdateModal && workspace?.updateCenter?.updateAvailable ? (
        <div className="update-modal">
          <article className="panel update-panel">
            <div className="panel-head">
              <h3>Update Available</h3>
              <span>{workspace.updateCenter.channel} channel</span>
            </div>
            <p>
              Version {workspace.updateCenter.latestVersion} is ready. Install the new build to get the latest assistant, tracking, and communication fixes.
            </p>
            <div className="stack-list">
              {workspace.updateCenter.releaseNotes.map((note) => (
                <div key={note} className="list-row"><small>{note}</small></div>
              ))}
            </div>
            <div className="suggestion-row">
              <button type="button" className="cta-link" onClick={handleUpdateNow}>Update Now</button>
              <button type="button" onClick={dismissUpdate}>Later</button>
            </div>
          </article>
        </div>
      ) : null}

      <div className="mobile-shell">
        <header className="zyro-topbar">
          <div className="brand-block compact">
            <button type="button" className="menu-button" aria-label="Open navigation" onClick={() => setDrawerOpen(true)}>
              <span />
              <span />
              <span />
            </button>
            <img className="brand-logo" src="/zyroai-logo.jpg" alt="ZyroAi logo" />
            <div>
              <h1>ZyroAi</h1>
              <p>{workspace?.profile?.title || t(workspace?.profile?.language || "en", "premiumAssistant")}</p>
            </div>
          </div>

          <div className="status-stack">
            <span className="status-pill accent">{workspace?.overview?.liveMode || "Executive"}</span>
            <span className="status-pill">{workspace?.settings?.automation?.dndMode ? t(workspace?.profile?.language || "en", "dndOn") : t(workspace?.profile?.language || "en", "dndOff")}</span>
          </div>
        </header>

        <section className="hero-strip">
          <div>
            <p className="eyebrow">ZyroAi OS</p>
            <h2>{localizedTabs.find((tab) => tab.key === activeTab)?.label || "Home"}</h2>
          </div>
          <div className="hero-meta">
            <span>{connectionState}</span>
            <span>{chiefDeviceId.slice(0, 12)}</span>
          </div>
        </section>

        {banner ? <section className="info-banner">{banner}</section> : null}

        {loadError && !workspace ? (
          <section className="page-grid">
            <article className="panel error-panel">
              <h3>ZyroAi could not load your workspace</h3>
              <p>{loadError}</p>
              <button type="button" onClick={loadWorkspace}>Retry</button>
            </article>
          </section>
        ) : (
          <main className="content-stage">{pageMap[activeTab]}</main>
        )}
      </div>
    </div>
  );
}
