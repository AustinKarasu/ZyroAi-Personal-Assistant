import { useEffect, useMemo, useRef, useState } from "react";

const periodLabels = ["weekly", "monthly", "yearly"];
const walkingSpeedThreshold = { min: 0.35, max: 2.6 };

function distanceBetween(a, b) {
  const earthRadius = 6371000;
  const toRadians = (value) => (value * Math.PI) / 180;
  const dLat = toRadians(b.latitude - a.latitude);
  const dLon = toRadians(b.longitude - a.longitude);
  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);
  const haversine = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * earthRadius * Math.asin(Math.sqrt(haversine));
}

function createDecisionOptions() {
  return [
    {
      name: "Finish what is already active",
      pros: "less context switching\nfaster visible wins\nlower overwhelm",
      cons: "new ideas wait"
    },
    {
      name: "Start the newest opportunity now",
      pros: "captures fresh momentum\npossible earlier upside",
      cons: "execution spread becomes wider\nexisting work slows"
    }
  ];
}

function parseList(value) {
  return value.split("\n").map((item) => item.trim()).filter(Boolean);
}

export default function IntelligencePage({ workspace, actions, busyKey }) {
  const [decisionTitle, setDecisionTitle] = useState("How should I sequence next week's priorities?");
  const [decisionOptions, setDecisionOptions] = useState(createDecisionOptions);
  const [decisionResult, setDecisionResult] = useState(null);
  const [hint, setHint] = useState("");
  const [note, setNote] = useState("");
  const [habitName, setHabitName] = useState("");
  const [stepCount, setStepCount] = useState(500);
  const [reportResult, setReportResult] = useState(workspace?.reports?.latest?.weekly || null);
  const [trackingState, setTrackingState] = useState("idle");
  const [weatherStatus, setWeatherStatus] = useState("");
  const [reportStatus, setReportStatus] = useState("");
  const lastPositionRef = useRef(null);
  const watchIdRef = useRef(null);

  const latestDecision = useMemo(() => workspace?.decisions?.[0] || null, [workspace?.decisions]);

  useEffect(() => {
    setReportResult(workspace?.reports?.latest?.weekly || null);
  }, [workspace]);

  useEffect(() => {
    const shouldTrack = Boolean(workspace?.settings?.automation?.autoStepTracking && workspace?.settings?.permissions?.location && workspace?.settings?.permissions?.activity);
    if (!shouldTrack || !navigator.geolocation || watchIdRef.current != null) {
      return undefined;
    }

    watchIdRef.current = navigator.geolocation.watchPosition(
      async (position) => {
        const current = {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          speed: position.coords.speed,
          timestamp: position.timestamp
        };

        if (!lastPositionRef.current) {
          lastPositionRef.current = current;
          setTrackingState("tracking");
          return;
        }

        const previous = lastPositionRef.current;
        lastPositionRef.current = current;
        const distanceMeters = distanceBetween(previous, current);
        const durationSeconds = Math.max(1, Math.round((current.timestamp - previous.timestamp) / 1000));
        const speedMps = current.speed ?? distanceMeters / durationSeconds;

        if (distanceMeters < 8) {
          setTrackingState("tracking");
          return;
        }

        const activityHint = speedMps > walkingSpeedThreshold.max ? "vehicle" : "walking";
        await actions.logSmartSteps({
          distance_meters: Number(distanceMeters.toFixed(2)),
          duration_seconds: durationSeconds,
          speed_mps: Number(speedMps.toFixed(2)),
          activity_hint: activityHint
        });
        setTrackingState(activityHint === "vehicle" ? "vehicle-filtered" : "tracking");
      },
      () => setTrackingState("permission-needed"),
      { enableHighAccuracy: true, maximumAge: 2000, timeout: 15000 }
    );

    return () => {
      if (watchIdRef.current != null) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
    };
  }, [actions, workspace?.settings?.automation?.autoStepTracking, workspace?.settings?.permissions?.activity, workspace?.settings?.permissions?.location]);

  if (!workspace) {
    return <section className="page-grid"><div className="panel loading-panel">Loading intelligence modules...</div></section>;
  }

  async function runDecision(event) {
    event.preventDefault();
    const options = decisionOptions
      .filter((option) => option.name.trim())
      .map((option) => ({
        name: option.name.trim(),
        pros: parseList(option.pros),
        cons: parseList(option.cons)
      }))
      .filter((option) => option.pros.length && option.cons.length);

    if (options.length < 2) {
      setDecisionResult({ error: "Add at least two complete options with pros and cons." });
      return;
    }

    const response = await actions.runDecision({
      title: decisionTitle,
      options
    });
    setDecisionResult(response);
  }

  async function saveMemory(event) {
    event.preventDefault();
    if (!hint.trim() || !note.trim()) return;
    await actions.saveMemory(hint.trim(), note.trim());
    setHint("");
    setNote("");
  }

  async function saveHabit(event) {
    event.preventDefault();
    if (!habitName.trim()) return;
    await actions.saveHabit(habitName.trim());
    setHabitName("");
  }

  async function refreshWeather() {
    if (!navigator.geolocation) {
      setTrackingState("browser-no-geo");
      setWeatherStatus("This browser does not expose geolocation.");
      return;
    }

    navigator.geolocation.getCurrentPosition(async (position) => {
      setWeatherStatus("Refreshing live weather...");
      await actions.saveSettings({ permissions: { location: true } });
      await actions.refreshWeather(position.coords.latitude, position.coords.longitude);
      setWeatherStatus("Weather refreshed from live coordinates.");
    }, () => {
      setTrackingState("permission-needed");
      setWeatherStatus("Location permission is needed to refresh weather.");
    }, { enableHighAccuracy: true, timeout: 12000 });
  }

  async function addSteps(event) {
    event.preventDefault();
    await actions.logSteps({ count: Number(stepCount), mode: "add", source: "manual" });
    setStepCount(500);
  }

  async function loadReport(period) {
    setReportStatus(`Generating ${period} report...`);
    const response = await actions.generateReport(period);
    setReportResult(response?.report || null);
    setReportStatus(`${period[0].toUpperCase()}${period.slice(1)} report updated.`);
  }

  async function enableSmartTracking() {
    await actions.saveSettings({
      automation: { autoStepTracking: true },
      permissions: { location: true, activity: true }
    });
    setTrackingState("arming");
  }

  async function stopSmartTracking() {
    if (watchIdRef.current != null && navigator.geolocation) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    lastPositionRef.current = null;
    setTrackingState("idle");
    await actions.saveSettings({ automation: { autoStepTracking: false } });
  }

  function updateDecisionOption(index, field, value) {
    setDecisionOptions((current) => current.map((option, optionIndex) => optionIndex === index ? { ...option, [field]: value } : option));
  }

  function addDecisionOption() {
    setDecisionOptions((current) => [...current, { name: "", pros: "", cons: "" }]);
  }

  return (
    <section className="page-grid">
      <article className="panel">
        <div className="panel-head">
          <h3>Weather and Movement</h3>
          <span>{workspace.steps.progress}% daily movement progress</span>
        </div>
        <div className="feature-grid">
          <div className="feature-card">
            <strong>Weather</strong>
            <p>{workspace.weather ? `${workspace.weather.summary} at ${workspace.weather.temperatureC} C` : "No live weather cached yet."}</p>
            <button type="button" onClick={refreshWeather} disabled={busyKey === "weather-refresh"}>Refresh Weather</button>
            <small>{weatherStatus || "Use location to refresh live weather."}</small>
          </div>
          <div className="feature-card">
            <strong>Footstep Tracker</strong>
            <p>{workspace.steps.count.toLocaleString()} / {workspace.steps.goal.toLocaleString()} steps today</p>
            <small>Smart tracking uses live location and ignores movement that looks like bus, bike, or car travel.</small>
            <div className="suggestion-row">
              <button type="button" className={workspace.settings.automation.autoStepTracking ? "active" : ""} onClick={enableSmartTracking} disabled={busyKey === "save-settings"}>Start Smart Tracking</button>
              <button type="button" onClick={stopSmartTracking} disabled={busyKey === "save-settings"}>Stop</button>
            </div>
            <div className="reply-card">
              <strong>Tracker state</strong>
              <p>{trackingState === "vehicle-filtered" ? "Vehicle-speed movement detected and ignored." : trackingState === "tracking" ? "Walking movement is being watched live." : trackingState === "permission-needed" ? "Location permission is needed to continue." : trackingState === "arming" ? "Smart tracker is being enabled." : "Tracker is idle."}</p>
            </div>
            <form className="inline-form" onSubmit={addSteps}>
              <input type="number" min="0" step="100" value={stepCount} onChange={(event) => setStepCount(event.target.value)} />
              <button type="submit" disabled={busyKey === "log-steps"}>Add Steps</button>
            </form>
          </div>
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>AI Reports</h3>
          <span>Weekly, monthly, yearly intelligence</span>
        </div>
        <div className="suggestion-row">
          {periodLabels.map((period) => (
            <button key={period} type="button" onClick={() => loadReport(period)} disabled={busyKey === `report-${period}`}>
              {period}
            </button>
          ))}
        </div>
        <div className="reply-card">
          <strong>{reportResult?.period || "weekly"} report</strong>
          <p>{reportResult?.highlights?.[0] || "Generate a report to review how work, calls, and movement are trending."}</p>
        </div>
        {reportStatus ? <div className="empty-card">{reportStatus}</div> : null}
        <div className="stack-list">
          {(reportResult?.highlights || []).map((item) => (
            <div key={item} className="list-row"><strong>{item}</strong></div>
          ))}
          {(reportResult?.coaching || []).map((item) => (
            <div key={item} className="list-row"><small>{item}</small></div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Decision Cockpit</h3>
          <span>{workspace.decisions.length} recent decisions</span>
        </div>
        <form className="page-grid" onSubmit={runDecision}>
          <label className="setting-field">
            <span>Decision title</span>
            <input value={decisionTitle} onChange={(event) => setDecisionTitle(event.target.value)} />
          </label>
          <div className="stack-list">
            {decisionOptions.map((option, index) => (
              <div key={`${index}-${option.name}`} className="panel">
                <div className="panel-head">
                  <strong>Option {index + 1}</strong>
                  <span>{option.name || "Unnamed"}</span>
                </div>
                <div className="form-grid">
                  <input value={option.name} onChange={(event) => updateDecisionOption(index, "name", event.target.value)} placeholder="Option name" />
                  <textarea value={option.pros} onChange={(event) => updateDecisionOption(index, "pros", event.target.value)} rows={4} placeholder="Pros, one per line" />
                  <textarea value={option.cons} onChange={(event) => updateDecisionOption(index, "cons", event.target.value)} rows={4} placeholder="Cons, one per line" />
                </div>
              </div>
            ))}
          </div>
          <div className="row-actions">
            <button type="button" onClick={addDecisionOption}>Add Option</button>
            <button type="submit" disabled={busyKey === "run-decision"}>Run Decision Model</button>
          </div>
        </form>
        <div className="reply-card">
          <strong>Latest recommendation</strong>
          <p>{decisionResult?.error || (decisionResult ? `${decisionResult.recommendation} at ${decisionResult.confidence}% confidence` : latestDecision?.recommendation || "No recommendation generated yet.")}</p>
        </div>
        <div className="stack-list">
          {(decisionResult?.breakdown || []).map((option) => (
            <div key={option.name} className="list-row">
              <div>
                <strong>{option.name}</strong>
                <small>{option.pros.length} pros and {option.cons.length} cons</small>
              </div>
              <span className="tier-pill tier-standard">Score {option.score}</span>
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Encrypted Memory Vault</h3>
          <span>{workspace.memories.length} retained notes</span>
        </div>
        <form className="form-grid" onSubmit={saveMemory}>
          <input value={hint} onChange={(event) => setHint(event.target.value)} placeholder="Hint or topic" />
          <textarea value={note} onChange={(event) => setNote(event.target.value)} rows={4} placeholder="Important detail to remember" />
          <button type="submit" disabled={busyKey === "save-memory"}>Save Memory</button>
        </form>
        <div className="stack-list">
          {workspace.memories.length === 0 ? <div className="empty-card">No memories saved yet.</div> : null}
          {workspace.memories.map((memory) => (
            <div key={memory.id} className="list-row">
              <div>
                <strong>{memory.hint}</strong>
                <small>{new Date(memory.created_at).toLocaleString()}</small>
              </div>
              <span className="tier-pill tier-standard">Encrypted</span>
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Wellbeing and Habit Engine</h3>
          <span>{workspace.habits.length} active rituals</span>
        </div>
        <form className="inline-form" onSubmit={saveHabit}>
          <input value={habitName} onChange={(event) => setHabitName(event.target.value)} placeholder="Add a new habit" />
          <button type="submit" disabled={busyKey === "save-habit"}>Add Habit</button>
        </form>
        <div className="habit-grid">
          {workspace.habits.length === 0 ? <div className="empty-card">No habits added yet.</div> : null}
          {workspace.habits.map((habit) => (
            <div key={habit.id} className="habit-card">
              <strong>{habit.name}</strong>
              <span>Streak {habit.streak}</span>
              <small>{habit.completed_today}/{habit.target_per_day} today</small>
              <button type="button" onClick={() => actions.checkInHabit(habit.id)} disabled={busyKey === `habit-${habit.id}`}>
                Check In
              </button>
            </div>
          ))}
        </div>
      </article>
    </section>
  );
}
