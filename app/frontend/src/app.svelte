<script lang="ts">
  import type { Client } from '@connectrpc/connect'

  import { Status } from '@/gen/armadarr/v1/health_pb'
  import type { HealthService } from '@/gen/armadarr/v1/health_pb'

  const { health }: { health: Client<typeof HealthService> } = $props()

  const check = $derived(health.check({}))
</script>

<h1>Hello world</h1>
{#await check then response}
  <p>Server: {response.status === Status.OK ? 'ok' : 'unknown'}</p>
{:catch}
  <p>Server: unreachable</p>
{/await}
