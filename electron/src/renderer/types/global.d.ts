import type { HelixAPI } from '../../preload/index'

declare global {
  interface Window {
    helix: HelixAPI
  }
}
