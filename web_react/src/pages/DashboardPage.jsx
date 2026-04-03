import { useEffect, useState } from "react";

const modes = ["Executive", "Deep Work", "Available", "Travel"];

export default function DashboardPage({ workspace, actions, busyKey }) {
  const [title, setTitle] = useState("");
  const [nowTime, setNowTime] = useState(() => new Date());

  useEffect(() => {
    const timer = setInterval(() => setNowTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  if (!workspace) {
    return <section className="page-grid"><div className="panel loading-panel">Loading ZyroAi home...</div></section>;
  }

  async function handleSubmit(event) {
    event.preventDefault();
    if (!title.trim()) return;
    await actions.createTask({
      title: title.trim(),
      urgency: 5,
      importance: 5,
      energyCost: 3,
      category: "Command",
      energyBand: "deep"
    });
    setTitle("");
  }

  return (
    <section className="page-grid">
      <article className="hero-panel">
        <div>
          <p className="eyebrow">ZyroAi Daily Brief</p>
          <h3>{workspace.profile.name} is in {workspace.overview.liveMode} mode with an executive score of {workspace.overview.executiveScore}</h3>
          <p className="hero-copy">
            {workspace.overview.automationStatus}. {workspace.notifications[0]?.detail || "ZyroAi is tracking your day in real time."}
          </p>
          <div className="status-cluster">
            <span className="status-pill">{nowTime.toLocaleDateString()}</span>
            <span className="status-pill accent">{nowTime.toLocaleTimeString()}</span>
            <span className="status-pill">{workspace.profile.timezone}</span>
          </div>
        </div>

        <div className="mode-strip">
          {modes.map((mode) => (
            <button
              key={mode}
              type="button"
              className={workspace.overview.liveMode === mode ? "active" : ""}
              onClick={() => actions.setMode(mode)}
              disabled={busyKey === `mode-${mode}`}
            >
              {mode}
            </button>
          ))}
        </div>

        <form className="quick-task-form" onSubmit={handleSubmit}>
          <input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            placeholder="Drop a high-impact task into ZyroAi"
          />
          <button type="submit" disabled={busyKey === "create-task"}>Add Priority</button>
        </form>
      </article>

      <div className="kpi-grid">
        {workspace.kpis.map((kpi) => (
          <article key={kpi.label} className={`metric-panel tone-${kpi.tone}`}>
            <span>{kpi.label}</span>
            <strong>{kpi.value}</strong>
            <small>{kpi.delta}</small>
          </article>
        ))}
      </div>

      <article className="panel">
        <div className="panel-head">
          <h3>Today at a Glance</h3>
          <span>{workspace.weather ? "Weather live" : "Cache ready"}</span>
        </div>
        <div className="feature-grid">
          <div className="feature-card">
            <strong>Weather</strong>
            <p>{workspace.weather ? `${workspace.weather.summary} at ${workspace.weather.temperatureC} C` : "Refresh weather from Intelligence once location is allowed."}</p>
          </div>
          <div className="feature-card">
            <strong>Footsteps</strong>
            <p>{workspace.steps.count.toLocaleString()} / {workspace.steps.goal.toLocaleString()} today</p>
          </div>
          <div className="feature-card">
            <strong>Weekly Report</strong>
            <p>{workspace.reports.latest.weekly.highlights[0]}</p>
          </div>
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Live Focus Blocks</h3>
          <span>{workspace.focusBlocks.length} blocks generated</span>
        </div>
        <div className="focus-list">
          {workspace.focusBlocks.length === 0 ? (
            <div className="empty-card">Add a few tasks and ZyroAi will generate focus blocks automatically.</div>
          ) : null}
          {workspace.focusBlocks.map((block) => (
            <div key={block.taskId} className="focus-item">
              <strong>{block.note}</strong>
              <span>Starts in {block.startInMinutes} min</span>
              <small>{block.durationMinutes} minute protected session</small>
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Agenda Timeline</h3>
          <span>{workspace.agenda.length} meetings</span>
        </div>
        <div className="timeline-list">
          {workspace.agenda.length === 0 ? (
            <div className="empty-card">No meetings yet. Use Planner to schedule your first one.</div>
          ) : null}
          {workspace.agenda.map((meeting) => (
            <div key={meeting.id} className="timeline-item">
              <strong>{meeting.title}</strong>
              <span>{new Date(meeting.start_at).toLocaleString()}</span>
              <small>{meeting.owner} - {meeting.duration_minutes} min</small>
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Alert Stack</h3>
          <span>{workspace.notifications.length} live updates</span>
        </div>
        <div className="alert-stack">
          {workspace.notifications.length === 0 ? (
            <div className="empty-card">No alerts yet. ZyroAi will surface activity here as you use the app.</div>
          ) : null}
          {workspace.notifications.map((item) => (
            <div key={item.id} className={`alert-card severity-${item.severity}`}>
              <strong>{item.title}</strong>
              <p>{item.detail}</p>
            </div>
          ))}
        </div>
      </article>
    </section>
  );
}
