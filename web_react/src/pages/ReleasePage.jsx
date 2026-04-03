export default function ReleasePage({ workspace }) {
  if (!workspace) {
    return <section className="page-grid"><div className="panel loading-panel">Loading update center...</div></section>;
  }

  return (
    <section className="page-grid">
      <article className="panel">
        <div className="panel-head">
          <h3>Update Center</h3>
          <span>{workspace.updateCenter.channel} channel</span>
        </div>
        <div className="reply-card">
          <strong>
            {workspace.updateCenter.updateAvailable
              ? `Version ${workspace.updateCenter.latestVersion} is ready`
              : `Version ${workspace.updateCenter.currentVersion} is current`}
          </strong>
          <p>
            ZyroAi uses an in-app update manifest so users can see new releases and choose when to upgrade.
          </p>
        </div>
        {workspace.updateCenter.downloadUrl ? (
          <a className="cta-link" href={workspace.updateCenter.downloadUrl} target="_blank" rel="noreferrer">
            Open Update Package
          </a>
        ) : null}
        <div className="stack-list">
          {workspace.updateCenter.releaseNotes.map((note) => (
            <div key={note} className="list-row"><small>{note}</small></div>
          ))}
        </div>
      </article>
    </section>
  );
}
