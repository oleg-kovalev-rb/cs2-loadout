import { createRoot } from 'react-dom/client'
import '../dashboard/styles/dashboard.css'
import { Dashboard } from '../dashboard/Dashboard'

const mountNode = document.getElementById('dashboard-root')
if (mountNode) {
  const apiUrl = mountNode.dataset.apiUrl
  createRoot(mountNode).render(<Dashboard apiUrl={apiUrl} />)
}
