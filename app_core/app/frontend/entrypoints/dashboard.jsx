import { createRoot } from 'react-dom/client'
import '../shared/styles/tokens.css'
import '../dashboard/styles/dashboard.css'
import { Dashboard } from '../dashboard/Dashboard'

const mountNode = document.getElementById('dashboard-root')
if (mountNode) {
  const { fetcherUrl, bridgeToken } = mountNode.dataset
  const demo = document.body.dataset.demo === 'true'
  const demoToken = document.body.dataset.demoToken

  createRoot(mountNode).render(
    <Dashboard
      fetcherUrl={fetcherUrl}
      bridgeToken={demo ? demoToken : bridgeToken}
      apiBase={demo ? '/api/demo' : '/api/v1'}
    />,
  )
}
