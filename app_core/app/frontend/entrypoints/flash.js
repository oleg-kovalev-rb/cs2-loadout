import { Application } from '@hotwired/stimulus'
import { FlashController } from '../controllers/flash_controller'

const application = Application.start()
application.register('flash', FlashController)
