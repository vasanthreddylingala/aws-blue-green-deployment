import React, { useState, useEffect } from 'react';

function App() {
  const [info, setInfo] = useState({ version: 'Loading...', environment: 'UNKNOWN' });
  const [tasks, setTasks] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch('/api/info')
      .then(res => res.json())
      .then(data => setInfo(data))
      .catch(err => setError('Backend API currently unreachable'));

    fetch('/api/tasks')
      .then(res => res.json())
      .then(data => setTasks(data))
      .catch(err => console.log('Tasks not loaded yet'));
  }, []);

  const isGreen = info.environment.toUpperCase() === 'GREEN';
  const bgColor = isGreen ? '#2e7d32' : '#1565c0';

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', padding: '30px', textAlign: 'center' }}>
      <div style={{
        backgroundColor: bgColor,
        color: '#fff',
        padding: '24px',
        borderRadius: '12px',
        boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
        maxWidth: '700px',
        margin: '0 auto'
      }}>
        <h1>AWS Blue-Green Deployment</h1>
        <h2>Active Environment: <span style={{ textDecoration: 'underline' }}>{info.environment}</span></h2>
        <h3>Application Version: {info.version}</h3>
      </div>

      <div style={{ maxWidth: '700px', margin: '30px auto', textAlign: 'left' }}>
        <h3>Database Tasks (Fetched from MySQL via Spring Boot):</h3>
        {error && <p style={{ color: 'red' }}>{error}</p>}
        <ul>
          {tasks.map(task => (
            <li key={task.id} style={{ margin: '8px 0' }}>
              <strong>{task.title}</strong> - {task.description} [<em>{task.status}</em>]
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

export default App;
