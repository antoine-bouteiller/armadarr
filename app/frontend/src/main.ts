import { createClient } from '@connectrpc/connect'
import { createConnectTransport } from '@connectrpc/connect-web'
import { mount } from 'svelte'

import App from '@/app.svelte'
import { HealthService } from '@/gen/armadarr/v1/health_pb'

const target = document.querySelector('#app')
if (target === null) {
  throw new Error('Missing #app element')
}

const transport = createConnectTransport({ baseUrl: '/api' })

mount(App, { props: { health: createClient(HealthService, transport) }, target })
