import { useEffect, useState } from "react";

const socialScopes = ["read_messages", "send_messages", "read_status"];

function SegmentedToggle({ label, description, value, onChange, disabled = false }) {
  return (
    <div className="setting-field">
      <span>{label}</span>
      <small>{description}</small>
      <div className="suggestion-row">
        <button type="button" className={value ? "active" : ""} onClick={() => onChange(true)} disabled={disabled}>On</button>
        <button type="button" className={!value ? "active" : ""} onClick={() => onChange(false)} disabled={disabled}>Off</button>
      </div>
    </div>
  );
}

export default function SettingsPage({ workspace, actions, busyKey }) {
  const settings = workspace?.settings;
  const profile = workspace?.profile;
  const [appearance, setAppearance] = useState(settings?.appearance || {});
  const [assistant, setAssistant] = useState(settings?.assistant || {});
  const [automation, setAutomation] = useState(settings?.automation || {});
  const [data, setData] = useState(settings?.data || {});
  const [permissions, setPermissions] = useState(settings?.permissions || {});
  const [integrations, setIntegrations] = useState(settings?.integrations || {});
  const [identity, setIdentity] = useState(profile || {});
  const [deviceInfo, setDeviceInfo] = useState({});
  const [permissionState, setPermissionState] = useState({});
  const [saveStatus, setSaveStatus] = useState("");

  useEffect(() => {
    if (!settings || !profile) return;
    setAppearance(settings.appearance || {});
    setAssistant(settings.assistant || {});
    setAutomation(settings.automation || {});
    setData(settings.data || {});
    setPermissions(settings.permissions || {});
    setIntegrations(settings.integrations || {});
    setIdentity(profile || {});
  }, [settings, profile]);

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = appearance.theme || settings?.appearance?.theme || "black-gold";
    root.dataset.density = appearance.density || settings?.appearance?.density || "comfortable";
    root.classList.toggle("reduced-motion", Boolean(appearance.reducedMotion));
  }, [appearance, settings]);

  useEffect(() => {
    setDeviceInfo({
      userAgent: navigator.userAgent,
      language: navigator.language,
      platform: navigator.userAgentData?.platform || navigator.platform || "Unknown",
      online: navigator.onLine ? "Online" : "Offline",
      cookiesEnabled: navigator.cookieEnabled ? "Enabled" : "Disabled",
      hardwareConcurrency: navigator.hardwareConcurrency || "Unknown",
      deviceMemory: navigator.deviceMemory ? `${navigator.deviceMemory} GB` : "Unknown",
      screen: `${window.screen.width} x ${window.screen.height}`,
      viewport: `${window.innerWidth} x ${window.innerHeight}`,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
    });

    async function loadPermissionState() {
      const next = {};
      if (navigator.permissions?.query) {
        const mapped = {
          location: "geolocation",
          notifications: "notifications",
          microphone: "microphone"
        };
        for (const [key, name] of Object.entries(mapped)) {
          try {
            const result = await navigator.permissions.query({ name });
            next[key] = result.state;
          } catch {
            next[key] = "unsupported";
          }
        }
      }
      next.activity = "app-controlled";
      setPermissionState(next);
    }

    loadPermissionState();
  }, []);

  if (!workspace || !settings || !profile) {
    return (
      <section className="page-grid">
        <div className="panel loading-panel">Loading settings...</div>
        <article className="panel support-footer">
          <div>
            <strong>Support</strong>
            <small>Need help with ZyroAi setup, updates, or device issues?</small>
          </div>
          <a className="cta-link" href="mailto:berrykarasu@gmail.com?subject=ZyroAi%20Support">Email Support</a>
        </article>
      </section>
    );
  }

  async function saveProfileSettings() {
    await actions.saveProfile({
      name: identity.name || "",
      title: identity.title || "",
      email: identity.email || "",
      avatar_url: identity.avatar_url || "",
      language: identity.language || "en",
      city: identity.city || "",
      daily_step_goal: Number(identity.daily_step_goal || 8000)
    });
    setSaveStatus("Profile saved.");
  }

  async function savePreferenceSettings() {
    await actions.saveSettings({ appearance, assistant, automation, data, permissions, integrations });
    setSaveStatus("Settings synced.");
  }

  async function persistSection(section, nextValue, setter) {
    setter(nextValue);
    await actions.saveSettings({ [section]: nextValue });
    setSaveStatus(`${section} updated.`);
  }

  async function requestPermission(key) {
    try {
      if (key === "notifications" && "Notification" in window) {
        const response = await Notification.requestPermission();
        const enabled = response === "granted";
        setPermissionState((current) => ({ ...current, notifications: response }));
        const nextPermissions = { ...permissions, notifications: enabled };
        setPermissions(nextPermissions);
        await actions.saveSettings({ permissions: { notifications: enabled } });
        setSaveStatus("Notification permission updated.");
        return;
      }

      if (key === "location" && navigator.geolocation) {
        await new Promise((resolve, reject) => {
          navigator.geolocation.getCurrentPosition(resolve, reject, { enableHighAccuracy: true, timeout: 12000 });
        });
        setPermissionState((current) => ({ ...current, location: "granted" }));
        const nextPermissions = { ...permissions, location: true };
        setPermissions(nextPermissions);
        await actions.saveSettings({ permissions: { location: true } });
        setSaveStatus("Location permission updated.");
        return;
      }

      if (key === "microphone" && navigator.mediaDevices?.getUserMedia) {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        stream.getTracks().forEach((track) => track.stop());
        setPermissionState((current) => ({ ...current, microphone: "granted" }));
        const nextPermissions = { ...permissions, microphone: true };
        setPermissions(nextPermissions);
        await actions.saveSettings({ permissions: { microphone: true } });
        setSaveStatus("Microphone permission updated.");
        return;
      }

      if (key === "activity") {
        setPermissionState((current) => ({ ...current, activity: "enabled" }));
        const nextPermissions = { ...permissions, activity: true };
        setPermissions(nextPermissions);
        await actions.saveSettings({ permissions: { activity: true } });
        setSaveStatus("Activity permission updated.");
      }
    } catch {
      setPermissionState((current) => ({ ...current, [key]: "denied" }));
      const nextPermissions = { ...permissions, [key]: false };
      setPermissions(nextPermissions);
      await actions.saveSettings({ permissions: { [key]: false } });
      setSaveStatus(`${key} permission denied.`);
    }
  }

  async function disablePermission(key) {
    const nextPermissions = { ...permissions, [key]: false };
    setPermissions(nextPermissions);
    await actions.saveSettings({ permissions: { [key]: false } });
    setSaveStatus(`${key} permission disabled.`);
  }

  async function authorizePlatform(platform) {
    const confirmed = window.confirm(`Authorize ${platform} for ${socialScopes.join(", ")} access inside ZyroAi? Official platform approval is still required for true live messaging.`);
    if (!confirmed) return;
    await actions.authorizeIntegration(platform, socialScopes);
    const nextIntegrations = {
      ...integrations,
      [platform]: {
        ...(integrations[platform] || {}),
        connected: true,
        status: "authorized",
        mode: "consent-granted",
        permissions: socialScopes,
        last_synced_at: new Date().toISOString()
      }
    };
    setIntegrations(nextIntegrations);
    setSaveStatus(`${platform} authorization saved.`);
  }

  return (
    <section className="page-grid">
      <article className="panel">
        <div className="panel-head">
          <h3>Profile</h3>
          <span>Identity, language, goals</span>
        </div>
        <div className="settings-grid">
          <label className="setting-field">
            <span>Name</span>
            <input value={identity.name || ""} onChange={(event) => setIdentity({ ...identity, name: event.target.value })} />
          </label>
          <label className="setting-field">
            <span>Title</span>
            <input value={identity.title || ""} onChange={(event) => setIdentity({ ...identity, title: event.target.value })} />
          </label>
          <label className="setting-field">
            <span>Email</span>
            <input value={identity.email || ""} onChange={(event) => setIdentity({ ...identity, email: event.target.value })} />
          </label>
          <label className="setting-field">
            <span>Avatar URL</span>
            <input value={identity.avatar_url || ""} onChange={(event) => setIdentity({ ...identity, avatar_url: event.target.value })} placeholder="https://..." />
          </label>
          <label className="setting-field">
            <span>Language</span>
            <select value={identity.language || "en"} onChange={(event) => setIdentity({ ...identity, language: event.target.value })}>
              <option value="en">English</option>
              <option value="hi">Hindi</option>
              <option value="es">Spanish</option>
              <option value="ar">Arabic</option>
            </select>
          </label>
          <label className="setting-field">
            <span>Daily step goal</span>
            <input type="number" min="1000" max="50000" value={identity.daily_step_goal || 8000} onChange={(event) => setIdentity({ ...identity, daily_step_goal: event.target.value })} />
          </label>
          <label className="setting-field">
            <span>City</span>
            <input value={identity.city || ""} onChange={(event) => setIdentity({ ...identity, city: event.target.value })} />
          </label>
        </div>
        <button type="button" onClick={saveProfileSettings} disabled={busyKey === "save-profile"}>Save Profile</button>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Automation</h3>
          <span>Call handling, reports, movement</span>
        </div>
        <div className="settings-grid">
          <SegmentedToggle label="DND mode" description="AI will shield calls while you are busy." value={Boolean(automation.dndMode)} onChange={(value) => persistSection("automation", { ...automation, dndMode: value }, setAutomation)} disabled={busyKey === "save-settings"} />
          <SegmentedToggle label="Call auto-reply" description="Respond with the busy message automatically." value={Boolean(automation.callAutoReply)} onChange={(value) => persistSection("automation", { ...automation, callAutoReply: value }, setAutomation)} disabled={busyKey === "save-settings"} />
          <SegmentedToggle label="Smart step tracking" description="Auto-add walking steps and ignore vehicle travel." value={Boolean(automation.autoStepTracking)} onChange={(value) => persistSection("automation", { ...automation, autoStepTracking: value }, setAutomation)} disabled={busyKey === "save-settings"} />
          <SegmentedToggle label="Weekly reports" description="Generate AI review summaries automatically." value={Boolean(assistant.weeklyReports)} onChange={(value) => persistSection("assistant", { ...assistant, weeklyReports: value }, setAssistant)} disabled={busyKey === "save-settings"} />
          <SegmentedToggle label="Monthly reports" description="Keep monthly productivity summaries ready." value={Boolean(assistant.monthlyReports)} onChange={(value) => persistSection("assistant", { ...assistant, monthlyReports: value }, setAssistant)} disabled={busyKey === "save-settings"} />
          <SegmentedToggle label="Yearly reports" description="Track long-term performance trends." value={Boolean(assistant.yearlyReports)} onChange={(value) => persistSection("assistant", { ...assistant, yearlyReports: value }, setAssistant)} disabled={busyKey === "save-settings"} />
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Permissions</h3>
          <span>Request and persist real access</span>
        </div>
        <div className="settings-grid">
          {[
            ["location", "Location access", "Needed for weather and smart walking detection."],
            ["activity", "Movement access", "Used with location to filter out bus or bike travel."],
            ["notifications", "Notifications", "Needed for executive alerts and reminders."],
            ["microphone", "Microphone", "Used for live speech translation and assistant voice input."]
          ].map(([key, title, description]) => (
            <div key={key} className="setting-field">
              <span>{title}</span>
              <small>{description}</small>
              <div className="panel-head">
                <span className={`tier-pill ${permissions[key] ? "tier-vip" : "tier-standard"}`}>{permissions[key] ? "Enabled" : "Disabled"}</span>
                <small>{permissionState[key] || "unknown"}</small>
              </div>
              <div className="suggestion-row">
                <button type="button" onClick={() => requestPermission(key)} disabled={busyKey === "save-settings"}>Authorize</button>
                <button type="button" className={!permissions[key] ? "active" : ""} onClick={() => disablePermission(key)} disabled={busyKey === "save-settings"}>Disable</button>
              </div>
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Appearance</h3>
          <span>Black premium design system</span>
        </div>
        <div className="settings-grid">
          <label className="setting-field">
            <span>Theme</span>
            <select value={appearance.theme || "black-gold"} onChange={(event) => setAppearance({ ...appearance, theme: event.target.value })}>
              <option value="black-gold">Black Gold</option>
              <option value="black-ice">Black Ice</option>
              <option value="obsidian-blue">Obsidian Blue</option>
            </select>
          </label>
          <label className="setting-field">
            <span>Density</span>
            <select value={appearance.density || "comfortable"} onChange={(event) => setAppearance({ ...appearance, density: event.target.value })}>
              <option value="comfortable">Comfortable</option>
              <option value="compact">Compact</option>
            </select>
          </label>
          <SegmentedToggle label="Reduced motion" description="Tone down transitions and animation." value={Boolean(appearance.reducedMotion)} onChange={(value) => setAppearance({ ...appearance, reducedMotion: value })} />
          <SegmentedToggle label="Realtime sync" description="Keep live device sync enabled when online." value={Boolean(data.realtimeSync)} onChange={(value) => setData({ ...data, realtimeSync: value })} />
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Social Integrations</h3>
          <span>Consent flow for connected messaging</span>
        </div>
        <div className="stack-list">
          {Object.entries(integrations).map(([platform, meta]) => (
            <div key={platform} className="list-row">
              <div>
                <strong>{platform}</strong>
                <small>{meta.connected ? `Authorized: ${(meta.permissions || []).join(", ") || "linked"}` : "Needs authorization"}</small>
              </div>
              <div className="suggestion-row">
                <span className={`tier-pill ${meta.connected ? "tier-vip" : "tier-standard"}`}>{meta.status || meta.mode || "manual"}</span>
                <button type="button" onClick={() => authorizePlatform(platform)} disabled={busyKey === `integration-${platform}`}>Authorize</button>
              </div>
            </div>
          ))}
        </div>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Audit Logs</h3>
          <span>{workspace.audit.length} recent actions</span>
        </div>
        <div className="stack-list">
          {workspace.audit.length === 0 ? <div className="empty-card">No audit entries yet.</div> : null}
          {workspace.audit.map((log) => (
            <div key={log.id} className="list-row">
              <div>
                <strong>{log.action}</strong>
                <small>{log.detail}</small>
              </div>
              <div className="right-copy">
                <span>{log.status}</span>
                <small>{new Date(log.created_at).toLocaleString()}</small>
              </div>
            </div>
          ))}
        </div>
        <button type="button" onClick={savePreferenceSettings} disabled={busyKey === "save-settings"}>Apply Visual and Data Settings</button>
      </article>

      <article className="panel">
        <div className="panel-head">
          <h3>Device Info</h3>
          <span>Live browser and display details</span>
        </div>
        <div className="stack-list">
          {Object.entries(deviceInfo).map(([key, value]) => (
            <div key={key} className="list-row">
              <strong>{key}</strong>
              <small>{String(value)}</small>
            </div>
          ))}
        </div>
      </article>

      <article className="panel support-footer">
        <div>
          <strong>Support</strong>
          <small>{saveStatus || "Need help with ZyroAi setup, updates, or device issues?"}</small>
        </div>
        <a className="cta-link" href="mailto:berrykarasu@gmail.com?subject=ZyroAi%20Support">Email Support</a>
      </article>
    </section>
  );
}
