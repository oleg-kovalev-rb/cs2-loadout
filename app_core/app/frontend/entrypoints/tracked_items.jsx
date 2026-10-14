import { createRoot } from 'react-dom/client'
import '../dashboard/styles/dashboard.css'
import '../tracked_items/styles/tracked_items.css'
import { TrackedItems } from '../tracked_items/TrackedItems'

const mountNode = document.getElementById('tracked-items-root')
if (mountNode) {
  const { fetcherUrl } = mountNode.dataset
  createRoot(mountNode).render(<TrackedItems fetcherUrl={fetcherUrl} />)
}
