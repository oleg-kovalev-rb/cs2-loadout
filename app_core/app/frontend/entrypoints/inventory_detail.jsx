import { createRoot } from 'react-dom/client'
import '../shared/styles/tokens.css'
import '../inventories/styles/inventories.css'
import { InventoryDetail } from '../inventories/InventoryDetail'

const mountNode = document.getElementById('inventory-detail-root')
if (mountNode) {
  const { fetcherUrl, steamId, nickname, avatarUrl } = mountNode.dataset
  createRoot(mountNode).render(
    <InventoryDetail
      fetcherUrl={fetcherUrl}
      steamId={steamId}
      profile={{ nickname: nickname || undefined, avatarUrl: avatarUrl || undefined }}
    />,
  )
}
