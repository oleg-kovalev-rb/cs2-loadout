import { createRoot } from 'react-dom/client'
import '../shared/styles/tokens.css'
import '../inventories/styles/inventories.css'
import { InventoryDetail } from '../inventories/InventoryDetail'

const mountNode = document.getElementById('inventory-detail-root')
if (mountNode) {
  const { fetcherUrl, steamId, nickname, avatarUrl } = mountNode.dataset
  const demo = mountNode.dataset.demoInventory === 'true'
  const demoToken = document.body.dataset.demoToken
  const apiBase = demo ? '/api/demo' : '/api/public'

  createRoot(mountNode).render(
    <InventoryDetail
      fetcherUrl={fetcherUrl}
      steamId={steamId}
      profile={{ nickname: nickname || undefined, avatarUrl: avatarUrl || undefined }}
      demo={demo}
      demoToken={demoToken}
      apiBase={apiBase}
    />,
  )
}
