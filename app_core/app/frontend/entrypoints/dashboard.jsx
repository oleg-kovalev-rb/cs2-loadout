import { createRoot } from 'react-dom/client'
import '../dashboard/styles/dashboard.css'
import { Dashboard } from '../dashboard/Dashboard'

const mountNode = document.getElementById('dashboard-root')
if (mountNode) {
  const { fetcherUrl, bridgeToken } = mountNode.dataset
  createRoot(mountNode).render(<Dashboard fetcherUrl={fetcherUrl} bridgeToken={bridgeToken} />)
}
