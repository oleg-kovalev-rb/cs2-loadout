import { createRoot } from 'react-dom/client'
import '../shared/styles/tokens.css'
import '../admin-panel/styles/admin-panel.css'
import { AdminPanel } from '../admin-panel/AdminPanel'

const mountNode = document.getElementById('admin-panel-root')
if (mountNode) {
  const { fetcherUrl, bridgeToken } = mountNode.dataset
  createRoot(mountNode).render(<AdminPanel fetcherUrl={fetcherUrl} bridgeToken={bridgeToken} />)
}
