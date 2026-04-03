const periodDays = {
  weekly: 7,
  monthly: 30,
  yearly: 365
};

const startOfWindow = (days) => new Date(Date.now() - days * 24 * 60 * 60 * 1000);
const isWithinWindow = (dateString, days) => {
  if (!dateString) return false;
  return new Date(dateString).getTime() >= startOfWindow(days).getTime();
};

export const buildPeriodReport = (workspace, period = "weekly") => {
  const days = periodDays[period] || 7;
  const recentTasks = workspace.tasks.filter((task) => isWithinWindow(task.created_at, days));
  const completedTasks = workspace.tasks.filter((task) => task.completed_at && isWithinWindow(task.completed_at, days));
  const recentCalls = workspace.call_logs.filter((log) => isWithinWindow(log.created_at, days));
  const urgentCalls = recentCalls.filter((log) => log.urgency >= 75);
  const recentMeetings = workspace.meetings.filter((meeting) => isWithinWindow(meeting.start_at, days));
  const recentSteps = workspace.step_entries.filter((entry) => isWithinWindow(`${entry.date}T00:00:00.000Z`, days));
  const totalSteps = recentSteps.reduce((sum, entry) => sum + Number(entry.count || 0), 0);
  const avgSteps = recentSteps.length ? Math.round(totalSteps / recentSteps.length) : 0;
  const completionRate = recentTasks.length ? Math.round((completedTasks.length / recentTasks.length) * 100) : 0;
  const focusScore = Math.max(38, Math.min(99, 55 + completionRate - urgentCalls.length * 3 + Math.min(recentMeetings.length, 10)));

  const highlights = [
    completedTasks.length > 0
      ? `${completedTasks.length} tasks were completed in the ${period} window.`
      : `No tasks were marked complete in the ${period} window yet.`,
    urgentCalls.length > 0
      ? `${urgentCalls.length} urgent communication items were detected.`
      : "No urgent communications broke through your flow.",
    totalSteps > 0
      ? `You logged ${totalSteps.toLocaleString()} steps with an average of ${avgSteps.toLocaleString()} per active day.`
      : "No step data was captured for this reporting period.",
    recentMeetings.length > 0
      ? `${recentMeetings.length} meetings were scheduled or held.`
      : "Meeting load stayed light during this period."
  ];

  const coaching = [
    completionRate >= 70 ? "Execution stayed strong. Protect the same focus windows next period." : "Protect more uninterrupted focus blocks to improve execution rate.",
    avgSteps >= 6000 ? "Movement stayed healthy. Keep the same habit cadence." : "Increase walking or step check-ins to improve physical momentum.",
    urgentCalls.length > 0 ? "Review VIP and DND rules to reduce noisy escalations." : "Your communication boundaries held up well."
  ];

  return {
    period,
    generatedAt: new Date().toISOString(),
    metrics: {
      focusScore,
      taskCount: recentTasks.length,
      completedTasks: completedTasks.length,
      completionRate,
      urgentCalls: urgentCalls.length,
      meetingCount: recentMeetings.length,
      totalSteps,
      averageSteps: avgSteps
    },
    highlights,
    coaching
  };
};
