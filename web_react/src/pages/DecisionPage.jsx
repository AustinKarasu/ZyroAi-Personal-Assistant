import { useState } from 'react';
import { decide } from '../api/client';

export default function DecisionPage() {
  const [result, setResult] = useState('No recommendation yet.');

  async function run() {
    const response = await decide({
      title: 'How should we launch?',
      options: [
        { name: 'Mobile First', pros: ['faster', 'focused delivery'], cons: ['web waits'] },
        { name: 'All Platforms', pros: ['single launch'], cons: ['higher risk', 'longer QA'] }
      ]
    });
    setResult(`Recommend: ${response.recommendation} (${response.confidence}% confidence)`);
  }

  return (
    <section className="page panel">
      <h2>Decision Lab</h2>
      <p>Run weighted AI support for high-impact decisions.</p>
      <button onClick={run}>Run Decision</button>
      <p className="result">{result}</p>
    </section>
  );
}
