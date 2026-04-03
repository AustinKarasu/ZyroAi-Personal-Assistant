import { useDeferredValue, useState } from "react";

const columns = [
  { key: "todo", label: "Queued" },
  { key: "in_progress", label: "In Motion" },
  { key: "done", label: "Complete" }
];

const statusActions = {
  todo: "in_progress",
  in_progress: "done",
  done: "todo"
};

export default function PlannerPage({ workspace, actions, busyKey }) {
  const [query, setQuery] = useState("");
  const [meeting, setMeeting] = useState({
    title: "",
    owner: "",
    startAt: "",
    durationMinutes: 30,
    notes: ""
  });
  const deferredQuery = useDeferredValue(query);

  if (!workspace) {
    return <section className="page-grid"><div className="panel loading-panel">Loading planner...</div></section>;
  }

  const filtered = workspace.tasks.all.filter((task) =>
    task.title.toLowerCase().includes(deferredQuery.toLowerCase()) ||
    task.category.toLowerCase().includes(deferredQuery.toLowerCase())
  );

  const grouped = {
    todo: filtered.filter((task) => task.status === "todo"),
    in_progress: filtered.filter((task) => task.status === "in_progress"),
    done: filtered.filter((task) => task.status === "done")
  };

  async function handleMeetingSubmit(event) {
    event.preventDefault();
    if (!meeting.title || !meeting.owner || !meeting.startAt || !meeting.notes) return;
    await actions.saveMeeting({
      ...meeting,
      startAt: new Date(meeting.startAt).toISOString(),
      durationMinutes: Number(meeting.durationMinutes)
    });
    setMeeting({ title: "", owner: "", startAt: "", durationMinutes: 30, notes: "" });
  }

  return (
    <section className="page-grid">
      <article className="panel">
        <div className="panel-head">
          <h3>Priority Pipeline</h3>
          <span>{workspace.tasks.all.length} tracked tasks</span>
        </div>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search by task title or category"
        />
        <div className="board-grid">
          {columns.map((column) => (
            <div key={column.key} className="board-column">
              <div className="board-head">
                <strong>{column.label}</strong>
                <span>{grouped[column.key].length}</span>
              </div>

              {grouped[column.key].length === 0 ? (
                <div className="empty-card">No items in this stage yet.</div>
              ) : null}

              {grouped[column.key].map((task) => (
                <div key={task.id} className="task-card">
                  <div className="task-meta">
                    <span>{task.category}</span>
                    <span>Score {task.priority_score}</span>
                  </div>
                  <strong>{task.title}</strong>
                  <small>{task.energy_band} energy band</small>
                  <button
                    type="button"
                    onClick={() => actions.setTaskStatus(task.id, statusActions[column.key])}
                    disabled={busyKey === `task-${task.id}`}
                  >
                    Move to {statusActions[column.key].replace("_", " ")}
                  </button>
                </div>
              ))}
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Meeting Builder</h3>
          <span>Action-item capture ready</span>
        </div>
        <form className="form-grid" onSubmit={handleMeetingSubmit}>
          <input
            value={meeting.title}
            onChange={(event) => setMeeting({ ...meeting, title: event.target.value })}
            placeholder="Meeting title"
          />
          <input
            value={meeting.owner}
            onChange={(event) => setMeeting({ ...meeting, owner: event.target.value })}
            placeholder="Owner"
          />
          <input
            type="datetime-local"
            value={meeting.startAt}
            onChange={(event) => setMeeting({ ...meeting, startAt: event.target.value })}
          />
          <input
            type="number"
            min="15"
            max="180"
            value={meeting.durationMinutes}
            onChange={(event) => setMeeting({ ...meeting, durationMinutes: event.target.value })}
            placeholder="Duration"
          />
          <textarea
            value={meeting.notes}
            onChange={(event) => setMeeting({ ...meeting, notes: event.target.value })}
            placeholder="Agenda or expected action items"
            rows={4}
          />
          <button type="submit" disabled={busyKey === "save-meeting"}>Schedule Meeting</button>
        </form>
      </article>
    </section>
  );
}
