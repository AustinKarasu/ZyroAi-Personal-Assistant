import {
  getAssistantMessages,
  getDailyQuests,
  getModeState,
  getProfile,
  getSettings,
  getStepSummary,
  getStorageMode,
  getWeatherCache,
  listAuditLogs,
  listCallLogs,
  listContacts,
  listDecisions,
  listHabits,
  listMeetings,
  listMemories,
  listNotifications,
  listReportSnapshots,
  listTasks
} from "../db/index.js";
import { buildPeriodReport } from "./reports.js";
import { suggestFocusBlocks } from "./prioritization.js";
import { loadUpdateManifest } from "./updates.js";

const categorizeTasks = (tasks) => ({
  todo: tasks.filter((task) => task.status === "todo"),
  inProgress: tasks.filter((task) => task.status === "in_progress"),
  done: tasks.filter((task) => task.status === "done")
});

export const buildWorkspace = async (deviceId, clientVersion = "") => {
  const [
    tasks,
    meetings,
    calls,
    habits,
    contacts,
    notifications,
    memories,
    decisions,
    updateCenter,
    modeState,
    settings,
    profile,
    assistantMessages,
    dailyQuests,
    steps,
    weather,
    audit,
    reportSnapshots
  ] = await Promise.all([
    listTasks(deviceId),
    listMeetings(deviceId),
    listCallLogs(deviceId),
    listHabits(deviceId),
    listContacts(deviceId),
    listNotifications(deviceId).then((items) => items.slice(0, 8)),
    listMemories(deviceId).then((items) => items.slice(0, 6)),
    listDecisions(deviceId).then((items) => items.slice(0, 5)),
    loadUpdateManifest(clientVersion),
    getModeState(deviceId),
    getSettings(deviceId),
    getProfile(deviceId),
    getAssistantMessages(deviceId),
    getDailyQuests(deviceId),
    getStepSummary(deviceId),
    getWeatherCache(deviceId),
    listAuditLogs(deviceId).then((items) => items.slice(0, 20)),
    listReportSnapshots(deviceId).then((items) => items.slice(0, 6))
  ]);

  const focusBlocks = suggestFocusBlocks(tasks);
  const latestReports = {
    weekly: buildPeriodReport({ tasks, meetings, call_logs: calls, habits, contacts, memories, decisions, step_entries: steps.count ? [{ date: steps.date, count: steps.count }] : [] }, "weekly"),
    monthly: buildPeriodReport({ tasks, meetings, call_logs: calls, habits, contacts, memories, decisions, step_entries: steps.count ? [{ date: steps.date, count: steps.count }] : [] }, "monthly"),
    yearly: buildPeriodReport({ tasks, meetings, call_logs: calls, habits, contacts, memories, decisions, step_entries: steps.count ? [{ date: steps.date, count: steps.count }] : [] }, "yearly")
  };

  const openTasks = tasks.filter((task) => task.status !== "done").length;
  const urgentCalls = calls.filter((call) => call.urgency >= 75).length;
  const vipContacts = contacts.filter((contact) => contact.tier === "vip").length;
  const completedHabits = habits.filter((habit) => habit.completed_today >= habit.target_per_day).length;

  return {
    generatedAt: new Date().toISOString(),
    storageMode: getStorageMode(),
    profile,
    overview: {
      executiveScore: Math.max(62, Math.min(98, 79 + completedHabits * 2 - urgentCalls + vipContacts + Math.round(steps.progress / 20))),
      liveMode: modeState.mode,
      deepWorkUntil: modeState.deep_work_until,
      syncStatus: getStorageMode() === "supabase-postgres" ? "Supabase Postgres live" : getStorageMode() === "supabase-cloud" ? "Supabase cloud sync live" : "Local fallback active",
      automationStatus: settings.automation.dndMode ? "DND shielding active" : urgentCalls > 0 ? "Escalations waiting" : "Automation stable",
      securityStatus: "Encrypted personal memory enabled"
    },
    kpis: [
      { label: "Open priorities", value: String(openTasks), delta: `${tasks.filter((task) => task.priority_score >= 80).length} critical`, tone: "accent" },
      { label: "Meetings today", value: String(meetings.length), delta: "Action-item capture armed", tone: "info" },
      { label: "Habit completion", value: `${completedHabits}/${habits.length || 1}`, delta: "Wellbeing guard live", tone: "success" },
      { label: "Footsteps", value: steps.count.toLocaleString(), delta: `${steps.progress}% of goal`, tone: steps.progress >= 100 ? "success" : "warning" }
    ],
    agenda: meetings,
    tasks: {
      all: tasks,
      grouped: categorizeTasks(tasks)
    },
    focusBlocks,
    communications: {
      calls,
      urgentCount: urgentCalls,
      suggestedReplyContext: modeState.mode === "Deep Work" ? "deep_work" : "meeting"
    },
    habits,
    contacts,
    memories,
    notifications,
    decisions,
    settings,
    steps,
    weather,
    audit,
    reports: {
      latest: latestReports,
      snapshots: reportSnapshots
    },
    assistant: {
      messages: assistantMessages,
      suggestions: [
        "Plan my afternoon",
        "What should I handle first?",
        "Generate my weekly report",
        "How is the weather and step progress?"
      ]
    },
    quests: dailyQuests,
    updateCenter: {
      ...updateCenter,
      appName: "ZyroAi"
    },
    features: [
      "Live executive dashboard",
      "Dynamic priority engine",
      "Task pipeline board",
      "Deep work mode",
      "Meeting agenda timeline",
      "Focus block planner",
      "Communication triage",
      "Contextual auto-replies",
      "Call urgency analysis",
      "Encrypted memory vault",
      "Decision cockpit",
      "Predictive wellbeing habits",
      "VIP contact routing",
      "Emergency override protocol",
      "Realtime workspace feed",
      "Offline-ready workspace cache",
      "Weather intelligence",
      "Footstep tracker",
      "Weekly monthly yearly reports",
      "Daily wellness quests",
      "Audit logs",
      "Profile and permissions settings",
      "Supabase cloud persistence",
      "AI workspace assistant",
      "DND call handling",
      "Appearance and data settings"
    ]
  };
};
