import { createRoot } from 'react-dom/client'
import '../shared/styles/tokens.css'
import '../inventories/styles/inventories.css'
import { InventoriesIndex } from '../inventories/InventoriesIndex'

const mountNode = document.getElementById('inventories-root')
if (mountNode) {
  const { fetcherUrl } = mountNode.dataset
  createRoot(mountNode).render(<InventoriesIndex fetcherUrl={fetcherUrl} />)
}
